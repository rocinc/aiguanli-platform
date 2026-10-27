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
import { DraftBench } from '../../../helpers/draft-bench';
import { httpTransport } from '../../../helpers/writing-run';

const ESC_MS = 3000;

// Makes the text fields of a draft something to keep working on: each one gets a bench (hand
// edits, versions, "what else should change", a bar for a selected passage). What the form
// posts stays the text in the boxes, so sending or keeping a draft takes the version on screen
// and goes through the same revision as any edit. Words that changed are no longer words the
// person confirmed having read.
export default class DraftRefineController extends Controller<HTMLFormElement> {
  static targets = ['toggle', 'field', 'guard', 'reread'];

  static values = { url: String, scope: Object, texts: Object, pollMs: Number };

  declare readonly toggleTarget:HTMLInputElement;
  declare readonly hasToggleTarget:boolean;
  declare readonly fieldTargets:HTMLElement[];
  declare readonly guardTargets:HTMLButtonElement[];
  declare readonly rereadTarget:HTMLElement;
  declare readonly hasRereadTarget:boolean;
  declare readonly urlValue:string;
  declare readonly scopeValue:Record<string, string>;
  declare readonly textsValue:Record<string, string>;
  declare readonly pollMsValue:number;
  declare readonly hasPollMsValue:boolean;

  private readonly reread = () => {
    if (this.hasRereadTarget && this.acknowledgement?.checked) { this.rereadTarget.hidden = true; }
  };

  private benches:DraftBench[] = [];
  private armed?:number;
  private watched = '';

  connect() {
    this.benches = this.fieldTargets.map((root) => new DraftBench(root, {
      transport: httpTransport(this.urlValue),
      scope: this.scopeValue,
      texts: this.textsValue,
      pollMs: this.hasPollMsValue ? this.pollMsValue : undefined,
      onText: () => this.textChanged(),
      onBusy: () => this.busyChanged(),
    }));
    this.watched = this.snapshot();
    this.acknowledgement?.addEventListener('change', this.reread);
  }

  disconnect() {
    this.acknowledgement?.removeEventListener('change', this.reread);
    window.clearTimeout(this.armed);
    this.benches.forEach((bench) => bench.dispose());
    this.benches = [];
  }

  toggled() {
    if (this.hasToggleTarget && this.toggleTarget.checked) {
      window.requestAnimationFrame(() => this.benches[0]?.focus());
    }
  }

  keydown(event:KeyboardEvent) {
    if (event.key !== 'Escape' || event.defaultPrevented || !this.editing) { return; }

    event.preventDefault();
    event.stopPropagation();

    const busy = this.benches.find((bench) => bench.busy);
    if (busy) {
      busy.stop();
    } else if (this.benches.some((bench) => bench.dirty) && !this.armed) {
      this.arm(event.target as Node);
    } else {
      this.leave();
    }
  }

  private get acknowledgement():HTMLInputElement|null {
    return this.element.elements.namedItem('acknowledged') as HTMLInputElement|null;
  }

  private get editing():boolean {
    return !this.hasToggleTarget || this.toggleTarget.checked;
  }

  private arm(from:Node) {
    const bench = this.benches.find((candidate) => candidate.contains(from)) ?? this.benches.find((candidate) => candidate.dirty)!;
    bench.say(this.textsValue.leave_confirm);
    this.armed = window.setTimeout(() => {
      this.armed = undefined;
      bench.say('');
    }, ESC_MS);
  }

  private leave() {
    window.clearTimeout(this.armed);
    this.armed = undefined;
    this.benches.forEach((bench) => bench.reset());
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = false;
      this.toggleTarget.focus();
    }
  }

  private textChanged() {
    window.clearTimeout(this.armed);
    this.armed = undefined;

    const now = this.snapshot();
    if (now === this.watched) { return; }
    this.watched = now;

    const box = this.acknowledgement;
    if (box?.checked) {
      box.checked = false;
      if (this.hasRereadTarget) { this.rereadTarget.hidden = false; }
    }
  }

  private busyChanged() {
    const busy = this.benches.some((bench) => bench.busy);
    this.guardTargets.forEach((button) => { button.disabled = busy; });
    this.element.toggleAttribute('aria-busy', busy);
  }

  private snapshot():string {
    return JSON.stringify(this.benches.map((bench) => bench.text));
  }
}
