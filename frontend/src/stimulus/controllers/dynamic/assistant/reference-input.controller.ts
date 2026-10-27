//-- copyright
// OpenProject is an open source project management software.
// Copyright (C) the OpenProject GmbH
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License version 3.
//
// OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
// Copyright (C) 2006-2013 Jean-Philippe Lang
// Copyright (C) 2010-2013 the ChiliProject Team
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
//
// See COPYRIGHT and LICENSE files for more details.
//++

import { Controller } from '@hotwired/stimulus';

interface Reference {
  kind:string;
  label:string;
  text:string;
}

const TRIGGER = /(^|\s)([@#])([^\s@#]{0,30})$/;
const DEBOUNCE_MS = 150;

// The panel's input offers work packages, people and versions after an @
// or a # and puts the chosen one into the text; the assistant reads it as
// part of the question.
export default class ReferenceInputController extends Controller<HTMLElement> {
  static values = { url: String, context: String, none: String };

  static targets = ['input', 'list'];

  declare readonly urlValue:string;
  declare readonly contextValue:string;
  declare readonly noneValue:string;
  declare readonly inputTarget:HTMLTextAreaElement;
  declare readonly listTarget:HTMLUListElement;

  private items:Reference[] = [];
  private active = 0;
  private timer?:number;
  private request?:AbortController;
  private abortController = new AbortController();

  connect() {
    const { signal } = this.abortController;
    this.inputTarget.addEventListener('input', this.changed, { signal });
    this.inputTarget.addEventListener('keydown', this.keydown, { signal, capture: true });
    this.inputTarget.addEventListener('blur', this.blurred, { signal });
    this.listTarget.addEventListener('mousedown', this.picked, { signal });
  }

  disconnect() {
    window.clearTimeout(this.timer);
    this.request?.abort();
    this.abortController.abort();
  }

  private get token() {
    const before = this.inputTarget.value.slice(0, this.inputTarget.selectionStart);
    const match = TRIGGER.exec(before);
    if (!match) { return null; }

    return { trigger: match[2], term: match[3], start: before.length - match[2].length - match[3].length };
  }

  private changed = () => {
    window.clearTimeout(this.timer);
    if (!this.token) {
      this.close();
      return;
    }

    this.timer = window.setTimeout(() => { void this.search(); }, DEBOUNCE_MS);
  };

  private async search() {
    const token = this.token;
    if (!token) { return; }

    this.request?.abort();
    this.request = new AbortController();
    const url = new URL(this.urlValue, window.location.origin);
    url.searchParams.set('q', token.term);
    url.searchParams.set('trigger', token.trigger);
    if (this.contextValue) { url.searchParams.set('context', this.contextValue); }

    try {
      const response = await fetch(url.toString(), {
        headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
        credentials: 'same-origin',
        signal: this.request.signal,
      });
      if (!response.ok) { return; }

      this.items = await response.json() as Reference[];
      this.active = 0;
      this.render();
    } catch (error) {
      if ((error as Error).name !== 'AbortError') { this.close(); }
    }
  }

  private render() {
    this.listTarget.replaceChildren();
    if (this.items.length === 0) {
      const none = document.createElement('li');
      none.classList.add('assistant-panel--reference-none');
      none.textContent = this.noneValue;
      this.listTarget.append(none);
    }

    this.items.forEach((item, index) => {
      const option = document.createElement('li');
      option.id = `assistant-panel-reference-${index}`;
      option.setAttribute('role', 'option');
      option.classList.add('assistant-panel--reference');
      option.dataset.index = String(index);
      option.textContent = item.label;
      option.setAttribute('aria-selected', String(index === this.active));
      this.listTarget.append(option);
    });
    this.listTarget.hidden = false;
    this.inputTarget.setAttribute('aria-expanded', 'true');
    this.syncActive();
  }

  private syncActive() {
    this.listTarget.querySelectorAll('[role="option"]').forEach((option, index) => {
      option.setAttribute('aria-selected', String(index === this.active));
    });
    this.inputTarget.setAttribute('aria-activedescendant', this.items.length ? `assistant-panel-reference-${this.active}` : '');
  }

  private close() {
    this.items = [];
    this.listTarget.hidden = true;
    this.listTarget.replaceChildren();
    this.inputTarget.setAttribute('aria-expanded', 'false');
    this.inputTarget.removeAttribute('aria-activedescendant');
  }

  private get open() {
    return !this.listTarget.hidden;
  }

  private keydown = (event:KeyboardEvent) => {
    if (!this.open || event.isComposing) { return; }

    switch (event.key) {
      case 'ArrowDown':
      case 'ArrowUp': {
        if (this.items.length === 0) { return; }
        const step = event.key === 'ArrowDown' ? 1 : -1;
        this.active = (this.active + step + this.items.length) % this.items.length;
        this.syncActive();
        break;
      }
      case 'Enter':
      case 'Tab':
        if (this.items.length === 0) { this.close(); return; }
        this.choose(this.items[this.active]);
        break;
      case 'Escape':
        this.close();
        break;
      default:
        return;
    }
    event.preventDefault();
    event.stopImmediatePropagation();
  };

  private picked = (event:MouseEvent) => {
    const option = (event.target as HTMLElement).closest<HTMLElement>('[data-index]');
    if (!option) { return; }

    event.preventDefault();
    this.choose(this.items[Number(option.dataset.index)]);
  };

  private blurred = () => {
    window.setTimeout(() => this.close(), 100);
  };

  private choose(reference:Reference) {
    const token = this.token;
    const input = this.inputTarget;
    if (!token) { this.close(); return; }

    const caret = input.selectionStart;
    const after = input.value.slice(caret);
    const inserted = `${reference.text} `;
    input.value = input.value.slice(0, token.start) + inserted + after;
    const position = token.start + inserted.length;
    input.setSelectionRange(position, position);
    input.focus();
    this.close();
  }
}
