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
import type { FrameElement } from '@hotwired/turbo';
import Mousetrap from 'mousetrap';

const SHORTCUT = 'a';
const WORK_PACKAGE_PATH = /\/work_packages\/(?:details\/)?(\d+)(?:\/|$)/;
const INPUT = '#assistant-panel-input';

interface OpenTarget { context?:string; conversation?:string; pin?:boolean }

// A page change replaces the whole body, dialog included; an open panel is
// carried over so it is still there on the next page, with the answer being
// written and the question being typed.
let carried:{ conversation?:string; draft?:string }|null = null;

export default class PanelDialogController extends Controller<HTMLDialogElement> {
  static values = {
    src: String,
    shortcuts: { type: Boolean, default: true },
  };

  static targets = ['frame', 'failed'];

  declare srcValue:string;
  declare readonly shortcutsValue:boolean;
  declare readonly frameTarget:FrameElement;
  declare readonly failedTarget:HTMLTemplateElement;

  private baseSrc = '';
  private loadedSrc = '';
  private pageSrc = '';
  private pinned = false;
  private submitting = false;
  private refocus = false;
  private draft = '';
  private returnFocusTo:HTMLElement|null = null;
  private abortController = new AbortController();

  connect() {
    const { signal } = this.abortController;
    this.baseSrc = this.srcValue;
    if (this.shortcutsValue) {
      Mousetrap.bind(SHORTCUT, () => { this.open(); return false; });
    }
    document.addEventListener('click', this.openFromTrigger, { signal, capture: true });
    this.element.addEventListener('click', this.pinHistoryChoice, { signal });
    this.element.addEventListener('close', this.closed, { signal });
    this.element.addEventListener('keydown', this.escape, { signal });
    this.element.addEventListener('pointerenter', this.followPage, { signal });
    this.element.addEventListener('focusin', this.followPage, { signal });
    this.element.addEventListener('turbo:submit-start', () => { this.submitting = true; }, { signal });
    this.element.addEventListener('turbo:before-frame-render', this.rememberFocus, { signal });
    this.element.addEventListener('turbo:fetch-request-error', this.failed, { signal });
    this.element.addEventListener('turbo:frame-render', this.frameRendered, { signal });
    // Before the platform's handler, which would leave the page for the error.
    this.element.addEventListener('turbo:frame-missing', this.failed, { signal, capture: true });

    if (carried) {
      const { conversation, draft } = carried;
      carried = null;
      this.draft = draft ?? '';
      this.open(conversation ? { conversation } : {}, { focus: false });
    }
  }

  disconnect() {
    if (this.shortcutsValue) {
      Mousetrap.unbind(SHORTCUT);
    }
    if (this.element.open) {
      carried = {
        conversation: this.answering ? this.openConversation : undefined,
        draft: this.element.querySelector<HTMLTextAreaElement>(INPUT)?.value,
      };
    }
    document.body.classList.remove('has-assistant-panel');
    this.abortController.abort();
  }

  open(target:OpenTarget = {}, { focus = true, from = null }:{ focus?:boolean; from?:HTMLElement|null } = {}) {
    this.srcValue = this.srcFor(target);
    this.pinned = !!target.conversation || !!target.pin;
    this.pageSrc = this.srcFor({});

    if (!this.element.open) {
      this.returnFocusTo = from ?? document.activeElement as HTMLElement|null;
      // Not modal: the page stays in view and usable beside the panel.
      this.element.show();
      document.body.classList.add('has-assistant-panel');
    }
    this.load(focus);
  }

  // "New conversation" is about the page in front of the person now, which
  // after a page change is not the page the open conversation was about.
  fresh(event:Event) {
    event.preventDefault();
    const url = new URL(this.srcFor({}), window.location.origin);
    url.searchParams.set('fresh', '1');
    this.pinned = false;
    this.pageSrc = this.srcFor({});
    this.srcValue = url.pathname + url.search;
    this.loadedSrc = this.srcValue;
    this.refocus = true;
    this.navigate(this.srcValue);
  }

  retry() {
    this.loadedSrc = '';
    this.load(true);
  }

  private get openConversation() {
    return this.frameTarget.querySelector<HTMLElement>('[data-conversation-id]')?.dataset.conversationId;
  }

  private get answering() {
    return this.frameTarget.querySelector('[aria-busy="true"]') !== null;
  }

  private srcFor({ context, conversation }:OpenTarget) {
    const url = new URL(this.baseSrc, window.location.origin);
    if (conversation) {
      url.searchParams.delete('context');
      url.searchParams.set('conversation_id', conversation);
    } else if (context) {
      url.searchParams.set('context', context);
    } else {
      const workPackage = WORK_PACKAGE_PATH.exec(window.location.pathname)?.[1];
      if (workPackage) {
        url.searchParams.delete('context');
        url.searchParams.set('work_package_id', workPackage);
      }
    }
    return url.pathname + url.search;
  }

  private load(focus:boolean) {
    if (this.loadedSrc === this.srcValue) {
      if (focus) { this.focusInput(); }
      return;
    }
    this.loadedSrc = this.srcValue;
    this.navigate(this.srcValue);
    if (focus) { void this.frameTarget.loaded?.then(() => this.focusInput()); }
  }

  private navigate(src:string) {
    if (this.frameTarget.getAttribute('src') === src) {
      void this.frameTarget.reload();
    } else {
      this.frameTarget.src = src;
    }
  }

  // The panel opened on one page keeps showing it after the page changed
  // without a reload; as long as nothing is being written or answered, it
  // moves along with the page.
  private followPage = () => {
    if (!this.element.open || this.pinned || this.answering) { return; }
    if (this.srcFor({}) === this.pageSrc) { return; }
    if (this.element.querySelector<HTMLTextAreaElement>(INPUT)?.value.trim()) { return; }

    this.open();
  };

  private pinHistoryChoice = (event:MouseEvent) => {
    if ((event.target as HTMLElement).closest('.assistant-panel--history-item')) {
      this.pinned = true;
    }
  };

  // A failed or offline load leaves a sentence and a way to try again,
  // instead of a spinner that never stops; the next open loads afresh.
  // A question that could not be sent stays in the panel, which reports it.
  private failed = (event:Event) => {
    if (event.target !== this.frameTarget) { return; }

    event.preventDefault();
    event.stopPropagation();
    if (this.submitting) {
      this.submitting = false;
      return;
    }
    this.loadedSrc = '';
    this.frameTarget.replaceChildren(this.failedTarget.content.cloneNode(true));
    window.requestAnimationFrame(() => this.frameTarget.querySelector<HTMLButtonElement>('button')?.focus());
  };

  private rememberFocus = (event:Event) => {
    if (event.target === this.frameTarget) {
      this.refocus = this.frameTarget.contains(document.activeElement);
    }
  };

  private frameRendered = (event:Event) => {
    if (event.target !== this.frameTarget) { return; }

    const { fetchResponse } = (event as CustomEvent<{ fetchResponse?:{ succeeded:boolean } }>).detail ?? {};
    if (fetchResponse && !fetchResponse.succeeded) {
      this.failed(event);
      return;
    }

    this.submitting = false;
    const input = this.element.querySelector<HTMLTextAreaElement>(INPUT);
    if (this.draft && input && !input.value) { input.value = this.draft; }
    this.draft = '';
    if (this.refocus) {
      this.refocus = false;
      this.focusInput();
    }
  };

  private focusInput() {
    window.requestAnimationFrame(() => {
      this.element.querySelector<HTMLTextAreaElement>(INPUT)?.focus();
    });
  }

  private openFromTrigger = (event:MouseEvent) => {
    const trigger = (event.target as HTMLElement|null)?.closest<HTMLElement>(
      '[data-assistant-panel-open], [data-show-dialog-id="assistant-panel-dialog"]',
    );
    if (!trigger) { return; }

    event.preventDefault();
    event.stopPropagation();
    this.open(
      {
        context: trigger.dataset.assistantContext,
        conversation: trigger.dataset.assistantConversation,
        pin: trigger.dataset.assistantPin === 'true',
      },
      { from: trigger },
    );
  };

  private escape = (event:KeyboardEvent) => {
    if (event.key === 'Escape' && !event.defaultPrevented) {
      this.element.close();
    }
  };

  private closed = () => {
    document.body.classList.remove('has-assistant-panel');
    if (this.returnFocusTo?.isConnected) { this.returnFocusTo.focus(); }
    this.returnFocusTo = null;
  };
}
