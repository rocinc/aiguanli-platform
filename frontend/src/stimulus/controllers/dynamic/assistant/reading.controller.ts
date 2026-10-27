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
import { announce } from '@primer/live-region-element';

const MAX_POLLS = 60;
const FADE_AFTER_MS = 4000;

export default class ReadingController extends Controller<HTMLElement> {
  static values = {
    url: String,
    interval: { type: Number, default: 2500 },
  };

  declare readonly urlValue:string;
  declare readonly intervalValue:number;

  private timer?:number;
  private polls = 0;
  private abortController = new AbortController();

  connect() {
    this.schedule();
  }

  disconnect() {
    window.clearTimeout(this.timer);
    this.abortController.abort();
  }

  private schedule() {
    this.timer = window.setTimeout(() => { void this.poll(); }, this.intervalValue);
  }

  private async poll() {
    this.polls += 1;
    if (document.hidden && this.polls < MAX_POLLS) {
      this.schedule();
      return;
    }

    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: 'text/html' },
        credentials: 'same-origin',
        signal: this.abortController.signal,
      });
      if (!response.ok) {
        this.element.remove();
        return;
      }

      const template = document.createElement('template');
      template.innerHTML = (await response.text()).trim();
      const next = template.content.firstElementChild as HTMLElement|null;
      if (!next) { return; }

      const state = next.dataset.assistantReadingState;
      if (state === 'reading') {
        if (this.polls < MAX_POLLS) { this.schedule(); } else { this.element.remove(); }
        return;
      }

      this.element.replaceWith(next);
      // A status region inserted together with its text is often not read.
      const line = next.querySelector<HTMLElement>('[role="status"]')?.textContent?.trim();
      if (line) { void announce(line, { politeness: 'polite' }); }
      // The activity tab redraws what was noted under the comment on its own
      // poll; nudging it now saves the person up to ten seconds of waiting.
      document.dispatchEvent(new CustomEvent('work-package-updated'));
      if (state === 'nothing' || state === 'none') { this.fadeOut(next); }
    } catch (error) {
      if ((error as Error).name !== 'AbortError' && this.polls < MAX_POLLS) { this.schedule(); }
    }
  }

  private fadeOut(element:HTMLElement) {
    window.setTimeout(() => {
      element.classList.add('assistant-reading--gone');
      const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      window.setTimeout(() => element.remove(), reduce ? 0 : 600);
    }, FADE_AFTER_MS);
  }
}
