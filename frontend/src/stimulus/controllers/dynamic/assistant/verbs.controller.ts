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

const FOCUSABLE = 'input[type="search"], input[type="radio"]:checked, input[type="radio"], textarea, select';

// The verbs of a remembered thing: each opens a small panel in place (the
// panel itself is a Turbo frame the server fills), and closes again on Esc,
// on the same verb, or on cancel. Lists of people and meetings can be
// searched, sorted and chosen with the arrow keys; Enter sends.
export default class VerbsController extends Controller<HTMLElement> {
  static targets = ['panel', 'frame', 'trigger', 'more', 'choice', 'filter', 'sorter', 'submit', 'words'];

  static classes = ['open'];

  declare readonly panelTarget:HTMLElement;
  declare readonly frameTarget:HTMLElement;
  declare readonly triggerTargets:HTMLElement[];
  declare readonly moreTarget:HTMLDetailsElement;
  declare readonly hasMoreTarget:boolean;
  declare readonly choiceTargets:HTMLElement[];
  declare readonly filterTarget:HTMLInputElement;
  declare readonly hasFilterTarget:boolean;
  declare readonly sorterTarget:HTMLElement;
  declare readonly submitTarget:HTMLButtonElement;
  declare readonly hasSubmitTarget:boolean;
  declare readonly openClass:string;

  private current:HTMLElement|null = null;
  private byFreeTime = false;

  private readonly outsideClick = (event:Event) => {
    if (this.hasMoreTarget && !this.moreTarget.contains(event.target as Node)) {
      this.moreTarget.open = false;
    }
  };

  connect() {
    this.panelTarget.inert = true;
    this.frameTarget.addEventListener('turbo:frame-load', this.loaded);
    document.addEventListener('click', this.outsideClick);
  }

  disconnect() {
    this.frameTarget.removeEventListener('turbo:frame-load', this.loaded);
    document.removeEventListener('click', this.outsideClick);
  }

  open(event:Event) {
    const trigger = event.currentTarget as HTMLElement;
    if (this.hasMoreTarget) { this.moreTarget.open = false; }

    if (this.current === trigger && this.isOpen) {
      event.preventDefault();
      this.close();
      return;
    }

    this.current = trigger;
    this.triggerTargets.forEach((each) => each.setAttribute('aria-expanded', String(each === trigger)));
  }

  closeMenu() {
    if (this.hasMoreTarget) { this.moreTarget.open = false; }
  }

  close() {
    this.panelTarget.classList.remove(this.openClass);
    this.panelTarget.inert = true;
    this.triggerTargets.forEach((each) => each.setAttribute('aria-expanded', 'false'));
    this.current?.focus();
    this.current = null;
  }

  key(event:KeyboardEvent) {
    const target = event.target as HTMLElement;
    if (event.key === 'Escape') {
      event.stopPropagation();
      this.close();
    } else if (event.key === 'ArrowDown' && target === this.filterInput) {
      event.preventDefault();
      this.visibleRadios[0]?.focus();
    } else if (event.key === 'Enter' && target.tagName !== 'TEXTAREA' && target.tagName !== 'BUTTON') {
      event.preventDefault();
      this.send(target);
    }
  }

  chosen() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = !this.ready(this.submitTarget.form);
    }
  }

  filter() {
    const query = this.filterInput?.value.trim().toLowerCase() ?? '';
    this.choiceTargets.forEach((choice) => {
      const name = choice.dataset.name ?? choice.textContent?.toLowerCase() ?? '';
      choice.hidden = query !== '' && !name.includes(query);
    });
  }

  sort(event:Event) {
    const button = event.currentTarget as HTMLElement;
    this.byFreeTime = !this.byFreeTime;
    const key = this.byFreeTime ? 'free' : 'name';
    const sorted = [...this.choiceTargets].sort((a, b) => (
      this.byFreeTime
        ? Number(b.dataset[key]) - Number(a.dataset[key])
        : (a.dataset[key] ?? '').localeCompare(b.dataset[key] ?? '')
    ));
    sorted.forEach((choice) => choice.parentElement?.appendChild(choice));

    const other = button.dataset.alt ?? '';
    button.dataset.alt = button.textContent ?? '';
    button.textContent = other;
    button.setAttribute('aria-pressed', String(this.byFreeTime));
  }

  private readonly loaded = () => {
    this.panelTarget.inert = false;
    this.panelTarget.classList.add(this.openClass);
    const first = this.frameTarget.querySelector<HTMLElement>(FOCUSABLE);
    first?.focus();
  };

  private get isOpen() {
    return this.panelTarget.classList.contains(this.openClass);
  }

  private get filterInput() {
    return this.hasFilterTarget ? this.filterTarget : null;
  }

  private get visibleRadios() {
    return this.choiceTargets
      .filter((choice) => !choice.hidden)
      .map((choice) => choice.querySelector<HTMLInputElement>('input[type="radio"]'))
      .filter((radio):radio is HTMLInputElement => radio !== null);
  }

  // Enter in the search box picks the first match when nothing is picked yet.
  private send(target:HTMLElement) {
    if (target === this.filterInput && !this.visibleRadios.some((radio) => radio.checked)) {
      const first = this.visibleRadios[0];
      if (first) {
        first.checked = true;
        this.chosen();
      }
      return;
    }

    const form = target.closest('form');
    if (form && this.ready(form)) { form.requestSubmit(); }
  }

  private ready(form:HTMLFormElement|null) {
    if (form === null) { return false; }

    const groups = new Set(Array.from(form.querySelectorAll<HTMLInputElement>('input[type="radio"]')).map((radio) => radio.name));
    const picked = Array.from(groups).every((name) => form.querySelector(`input[type="radio"][name="${name}"]:checked`) !== null);
    const words = form.querySelector<HTMLTextAreaElement>('textarea');
    return picked && (words?.value.trim() ?? 'x') !== '';
  }
}
