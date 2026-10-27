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
import { renderStreamMessage } from '@hotwired/turbo';

export default class PanelController extends Controller<HTMLElement> {
  static targets = ['messages', 'input', 'form', 'submit', 'stop', 'tag', 'contextField', 'error', 'spinner', 'history'];

  static values = { busy: Boolean, sync: String };

  declare readonly messagesTarget:HTMLElement;
  declare readonly inputTarget:HTMLTextAreaElement;
  declare readonly formTarget:HTMLFormElement;
  declare readonly submitTarget:HTMLButtonElement;
  declare readonly stopTarget:HTMLButtonElement;
  declare readonly hasStopTarget:boolean;
  declare readonly tagTarget:HTMLElement;
  declare readonly hasTagTarget:boolean;
  declare readonly contextFieldTarget:HTMLInputElement;
  declare readonly hasContextFieldTarget:boolean;
  declare readonly errorTarget:HTMLElement;
  declare readonly hasErrorTarget:boolean;
  declare readonly spinnerTarget:HTMLElement;
  declare readonly hasSpinnerTarget:boolean;
  declare readonly historyTarget:HTMLDetailsElement;
  declare readonly hasHistoryTarget:boolean;
  declare readonly busyValue:boolean;
  declare readonly syncValue:string;

  private observer?:MutationObserver;
  private abortController = new AbortController();

  connect() {
    this.scrollToEnd();
    this.observer = new MutationObserver(() => { if (this.nearEnd) { this.scrollToEnd(); } });
    this.observer.observe(this.messagesTarget, { childList: true, subtree: true, characterData: true });
    this.syncBusy(this.busyValue);
    this.element.addEventListener('assistant:message-settled', this.settled);
    this.scroller.addEventListener('scroll', this.onScroll, { passive: true });
    const { signal } = this.abortController;
    this.formTarget.addEventListener('turbo:submit-end', this.submitEnded, { signal });
    document.addEventListener('click', this.closeHistoryOutside, { signal });
  }

  private onScroll = () => { this.scrolled(); };

  disconnect() {
    this.observer?.disconnect();
    this.element.removeEventListener('assistant:message-settled', this.settled);
    this.scroller.removeEventListener('scroll', this.onScroll);
    this.abortController.abort();
  }

  historyKeydown(event:KeyboardEvent) {
    if (event.key === 'Escape' && this.historyTarget.open) {
      event.preventDefault();
      this.historyTarget.open = false;
      this.historyTarget.querySelector('summary')?.focus();
    }
  }

  private closeHistoryOutside = (event:MouseEvent) => {
    if (this.hasHistoryTarget && this.historyTarget.open && !this.historyTarget.contains(event.target as Node)) {
      this.historyTarget.open = false;
    }
  };

  keydown(event:KeyboardEvent) {
    if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      if (this.inputTarget.value.trim() !== '' && !this.submitTarget.disabled) {
        this.formTarget.requestSubmit();
      }
    }
  }

  // A suggested question is asked as it stands, the way a typed one would be.
  ask(event:Event&{ params?:{ text?:string } }) {
    const text = event.params?.text?.trim();
    if (!text || this.submitTarget.disabled) { return; }

    this.inputTarget.value = text;
    this.formTarget.requestSubmit();
  }

  // Before the first question the page it was opened on can be left out.
  dropContext() {
    if (this.hasTagTarget) { this.tagTarget.remove(); }
    if (this.hasContextFieldTarget) { this.contextFieldTarget.remove(); }
    this.formTarget.removeAttribute('data-assistant--reference-input-context-value');
    this.inputTarget.focus();
  }

  async stop() {
    const { url } = this.stopTarget.dataset;
    if (!url) { return; }

    this.stopTarget.disabled = true;
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
    try {
      await fetch(url, {
        method: 'POST',
        headers: { 'X-CSRF-Token': token, 'X-Requested-With': 'XMLHttpRequest' },
        credentials: 'same-origin',
      });
    } finally {
      this.stopTarget.disabled = false;
    }
  }

  submitted() {
    if (this.hasErrorTarget) { this.errorTarget.hidden = true; }
    this.syncBusy(true);
    this.nearEnd = true;
  }

  // The form stays as it was, with the question in it, so it can be sent again.
  private submitEnded = (event:Event) => {
    if ((event as CustomEvent<{ success:boolean }>).detail.success) { return; }

    this.syncBusy(false);
    if (this.hasErrorTarget) { this.errorTarget.hidden = false; }
    this.inputTarget.focus();
  };

  // Following the text as it is written, unless the reader scrolled up to
  // read something: then the page stays where they are.
  private nearEnd = true;

  scrolled() {
    const scroller = this.scroller;
    this.nearEnd = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 48;
  }

  private get scroller():HTMLElement {
    return this.element.closest<HTMLElement>('.Overlay-body') ?? this.messagesTarget;
  }

  private settled = () => {
    const stillBusy = this.messagesTarget.querySelector('[aria-busy="true"]') !== null;
    this.syncBusy(stillBusy);
    const active = document.activeElement;
    const untouched = !active || active === document.body || this.formTarget.contains(active);
    if (!stillBusy && untouched) { this.inputTarget.focus(); }
    if (!stillBusy && this.syncValue) { void this.syncPage(); }
  };

  // What the conversation changed shows on the page behind it.
  private async syncPage() {
    try {
      const response = await fetch(this.syncValue, {
        headers: { Accept: 'text/vnd.turbo-stream.html', 'X-Requested-With': 'XMLHttpRequest' },
        credentials: 'same-origin',
      });
      if (response.status === 200) { renderStreamMessage(await response.text()); }
    } catch {
      // the page keeps showing what it showed
    }
  }

  private syncBusy(busy:boolean) {
    this.submitTarget.disabled = busy;
    if (this.hasStopTarget) { this.stopTarget.hidden = !busy; }
    if (this.hasSpinnerTarget) { this.spinnerTarget.hidden = !busy; }
  }

  private scrollToEnd() {
    const scroller = this.scroller;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    scroller.scrollTo({ top: scroller.scrollHeight, behavior: reduce ? 'auto' : 'smooth' });
  }
}
