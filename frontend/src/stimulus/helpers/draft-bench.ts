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

import {
  canRefineSelection, canUndoRefine, clampAnchor, commitEdit, createDraft, currentText, Draft, fitReplacement,
  goToVersion, isSubmitKey, measureTextareaRange, placeBar, pushVersion, replaceRange, undoRefine,
} from 'core-app/shared/components/editor/components/assistant-writing/assistant-writing.logic';
import { RunResult, WritingRun, WritingTransport } from './writing-run';

export interface BenchEnv {
  transport:WritingTransport;
  scope:Record<string, string>;
  texts:Record<string, string>;
  pollMs?:number;
  onText():void;
  onBusy():void;
}

type Activity = 'revise'|'refine';
interface Span { start:number; end:number }

const BAR_WIDTH = 320;
const BAR_GUTTER = 8;
const BAR_HEIGHT_GUESS = 84;
const SWAP_MS = 180;

// One text field of a draft as a piece of work: hand edits, versions, "what else should change"
// for the whole text, and a bar for a selected passage. It is the editor's writing loop on a
// plain textarea, sharing its pure logic and the backend's revise / refine_selection modes.
export class DraftBench {
  private draft:Draft;
  private readonly initial:string;
  private activity:Activity|null = null;
  private span:Span|null = null;
  private stream = '';
  private run:WritingRun|null = null;
  private bar:Span|null = null;
  private barHeight = BAR_HEIGHT_GUESS;
  private composing = false;
  private swapTimer?:number;

  constructor(readonly root:HTMLElement, private readonly env:BenchEnv) {
    this.initial = this.area.defaultValue;
    this.draft = createDraft(this.area.value);
    this.bind();
    this.render();
  }

  get busy():boolean { return this.run !== null; }

  get text():string { return currentText(this.draft); }

  get dirty():boolean { return this.draft.versions.length > 1 || this.text !== this.initial; }

  get barOpen():boolean { return this.bar !== null; }

  focus():void { this.area.focus(); }

  contains(node:Node|null):boolean { return !!node && this.root.contains(node); }

  say(text:string, kind:'info'|'error' = 'info'):void {
    const note = this.part('notice');
    note.textContent = text;
    note.hidden = !text;
    note.classList.toggle('assistant-bench--error', kind === 'error');
    note.setAttribute('role', kind === 'error' ? 'alert' : 'status');
  }

  reset():void {
    this.dispose();
    this.draft = createDraft(this.initial);
    this.area.value = this.initial;
    this.hideBar();
    this.say('');
    this.render();
    this.env.onText();
    this.env.onBusy();
  }

  stop():void { this.run?.stop(); }

  dispose():void {
    const run = this.run;
    this.run = null;
    run?.stop();
    window.clearTimeout(this.swapTimer);
    this.activity = null;
    this.span = null;
  }

  closeBar():void {
    const bar = this.bar;
    this.hideBar();
    if (bar) {
      this.area.focus({ preventScroll: true });
      this.area.setSelectionRange(bar.start, bar.end);
    }
  }

  revise(opinion:string):boolean {
    const text = opinion.trim();
    const previous = this.text;
    if (!text || !previous.trim() || this.busy) { return false; }

    void this.execute('revise', {
      input: this.root.dataset.material ?? previous,
      built_in: 'revise',
      previous,
      instruction: text,
      task_instruction: this.root.dataset.task,
      ...this.env.scope,
    }, null);
    return true;
  }

  refine(start:number, end:number, opinion:string):boolean {
    const text = opinion.trim();
    const whole = this.text;
    if (!text || this.busy || !canRefineSelection(whole, start, end)) { return false; }

    const background = this.root.dataset.task;
    void this.execute('refine', {
      input: whole,
      built_in: 'refine_selection',
      selection: whole.slice(start, end),
      instruction: background ? `${text}（稿子背景：${background}）` : text,
      ...this.env.scope,
    }, { start, end });
    return true;
  }

  private bind():void {
    const area = this.area;
    area.addEventListener('input', () => this.onInput());
    area.addEventListener('compositionstart', () => { this.composing = true; });
    area.addEventListener('compositionend', () => {
      this.composing = false;
      this.commit(area.value);
    });
    ['select', 'mouseup', 'keyup', 'scroll'].forEach((name) => area.addEventListener(name, () => this.syncBar()));
    area.addEventListener('keydown', (event) => this.areaKeydown(event));
    area.addEventListener('blur', (event) => {
      const next = event.relatedTarget as Node|null;
      if (!next || !this.part('bar').contains(next)) { this.hideBar(); }
    });

    this.part('prev').addEventListener('click', () => this.step(-1));
    this.part('next').addEventListener('click', () => this.step(1));
    this.part('undo').addEventListener('click', () => this.undo());
    this.part('stop').addEventListener('click', () => this.stop());

    const input = this.part<HTMLInputElement>('revise-input');
    input.addEventListener('keydown', (event) => this.enter(event, () => this.submitRevise()));
    this.part('revise-go').addEventListener('click', () => this.submitRevise());

    const barInput = this.part<HTMLInputElement>('bar-input');
    barInput.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        this.closeBar();
      } else {
        this.enter(event, () => this.refineFromBar(barInput.value));
      }
    });
    this.part('bar-go').addEventListener('click', () => this.refineFromBar(barInput.value));
    this.root.querySelectorAll<HTMLElement>('[data-role="chip"]').forEach((chip) => {
      chip.addEventListener('click', () => this.refineFromBar(chip.textContent ?? ''));
    });
    this.part('bar').addEventListener('mousedown', (event) => {
      if (!(event.target instanceof HTMLInputElement)) { event.preventDefault(); }
    });
  }

  private enter(event:KeyboardEvent, submit:() => void):void {
    if (event.key !== 'Enter') { return; }
    event.preventDefault();
    if (isSubmitKey(event)) { submit(); }
  }

  private submitRevise():void {
    const input = this.part<HTMLInputElement>('revise-input');
    if (this.revise(input.value)) { input.value = ''; }
  }

  private refineFromBar(opinion:string):void {
    const bar = this.bar;
    if (bar) { this.refine(bar.start, bar.end, opinion); }
  }

  private areaKeydown(event:KeyboardEvent):void {
    if (event.key === 'Escape' && this.bar) {
      event.preventDefault();
      event.stopPropagation();
      this.closeBar();
    } else if (event.key.toLowerCase() === 'z' && (event.ctrlKey || event.metaKey) && !event.shiftKey
      && canUndoRefine(this.draft)) {
      event.preventDefault();
      this.undo();
    }
  }

  private onInput():void {
    if (this.composing) { return; }
    this.commit(this.area.value);
    this.syncBar();
  }

  private commit(text:string):void {
    const next = commitEdit(this.draft, text);
    if (next === this.draft) { return; }
    this.draft = next;
    this.say('');
    this.render();
    this.env.onText();
  }

  private step(delta:number):void {
    if (this.busy) { return; }
    this.draft = goToVersion(this.draft, this.draft.index + delta);
    this.say('');
    this.hideBar();
    this.area.classList.add('-swap');
    window.clearTimeout(this.swapTimer);
    this.swapTimer = window.setTimeout(() => this.area.classList.remove('-swap'), SWAP_MS);
    this.render();
    this.env.onText();
  }

  private undo():void {
    if (this.busy || !canUndoRefine(this.draft)) { return; }
    this.draft = undoRefine(this.draft);
    this.say('');
    this.render();
    this.area.focus({ preventScroll: true });
    this.env.onText();
  }

  private async execute(activity:Activity, body:Record<string, unknown>, span:Span|null):Promise<void> {
    const height = this.area.offsetHeight;
    const run = new WritingRun(this.env.transport, (stream) => {
      this.stream = stream;
      this.renderPreview();
    }, this.env.pollMs);

    this.run = run;
    this.activity = activity;
    this.span = span;
    this.stream = '';
    this.hideBar();
    this.say('');
    this.part('preview').style.minHeight = height ? `${height}px` : '';
    this.render();
    this.env.onBusy();
    this.announce(this.env.texts[activity === 'revise' ? 'revising' : 'refining']);
    this.part('stop').focus();

    const result = await run.execute(body);
    if (this.run !== run) { return; }

    this.run = null;
    this.settle(result, activity, span);
  }

  private settle(result:RunResult, activity:Activity, span:Span|null):void {
    const text = result.text.trim();
    this.activity = null;
    this.span = null;

    if (result.status === 'succeeded' && text) {
      this.adopt(text, activity, span);
    } else {
      const failure = { revise: 'revise_failed', refine: 'refine_failed' }[activity];
      if (result.status === 'cancelled') {
        this.say(this.env.texts.stopped_kept);
      } else if (result.status === 'succeeded') {
        this.say(this.env.texts.empty_result, 'error');
      } else {
        this.say(this.env.texts[failure] || this.env.texts.failed, 'error');
      }
      this.render();
      this.focusAfter(activity, null);
    }
    this.env.onBusy();
  }

  private adopt(text:string, activity:Activity, span:Span|null):void {
    const whole = this.text;
    let caret:number|null = null;

    if (activity === 'refine' && span) {
      const replacement = fitReplacement(whole.slice(span.start, span.end), text);
      this.draft = pushVersion(this.draft, replaceRange(whole, span.start, span.end, replacement), 'refine');
      caret = span.start + replacement.length;
      this.announce(this.env.texts.refined);
    } else {
      this.draft = pushVersion(this.draft, text, 'revise');
      this.announce(this.env.texts.revised.replace('%{current}', String(this.draft.index + 1)));
    }
    this.render();
    this.focusAfter(activity, caret);
    this.env.onText();
  }

  private focusAfter(activity:Activity, caret:number|null):void {
    if (activity === 'refine') {
      const area = this.area;
      area.focus({ preventScroll: true });
      const end = caret ?? area.value.length;
      area.setSelectionRange(end, end);
    } else {
      this.part<HTMLInputElement>('revise-input').focus();
    }
  }

  private render():void {
    const busy = this.busy;
    const count = this.draft.versions.length;
    const index = this.draft.index;
    const area = this.area;
    const refined = !busy && canUndoRefine(this.draft);

    this.part('versions').hidden = busy || count < 2;
    const position = this.part('position');
    position.textContent = `${index + 1}/${count}`;
    position.setAttribute('aria-label', this.env.texts.version_position.replace('%{current}', String(index + 1)).replace('%{total}', String(count)));
    this.part<HTMLButtonElement>('prev').disabled = index === 0;
    this.part<HTMLButtonElement>('next').disabled = index === count - 1;

    area.hidden = busy;
    this.part('preview').hidden = !busy;
    if (!busy && area.value !== this.text) { area.value = this.text; }

    this.part('status').hidden = !busy;
    this.part('status-text').textContent = busy ? this.env.texts[this.activity === 'refine' ? 'refining' : 'revising'] : '';
    this.part('refined').hidden = !refined;
    this.part('hint').hidden = busy || refined;
    this.part<HTMLInputElement>('revise-input').disabled = busy;
    this.part<HTMLButtonElement>('revise-go').disabled = busy;
    if (busy) { this.renderPreview(); }
  }

  private renderPreview():void {
    const preview = this.part('preview');
    preview.replaceChildren();
    const whole = this.text;

    if (this.activity === 'refine' && this.span) {
      const mark = document.createElement('mark');
      mark.className = 'assistant-bench--mark';
      mark.classList.toggle('-waiting', !this.stream);
      mark.textContent = this.stream || whole.slice(this.span.start, this.span.end);
      preview.append(whole.slice(0, this.span.start), mark, whole.slice(this.span.end));
    } else {
      preview.textContent = this.stream || whole;
    }
  }

  private syncBar():void {
    const area = this.area;
    if (this.busy || area.hidden) { return; }

    const { selectionStart: start, selectionEnd: end } = area;
    if (!canRefineSelection(area.value, start, end)) {
      this.hideBarUnlessFocused();
      return;
    }

    const anchor = clampAnchor(measureTextareaRange(area, start, end), area.getBoundingClientRect());
    if (!anchor) {
      this.hideBar();
      return;
    }

    const box = this.root.getBoundingClientRect();
    const width = Math.max(0, Math.min(BAR_WIDTH, box.width - 2 * BAR_GUTTER));
    const placed = placeBar(anchor, { width, height: this.barHeight }, { left: box.left + BAR_GUTTER, right: box.right - BAR_GUTTER });
    const bar = this.part('bar');
    const opening = bar.hidden;

    this.bar = { start, end };
    bar.style.width = `${width}px`;
    bar.style.left = `${placed.left - box.left}px`;
    bar.style.top = `${placed.top - box.top}px`;
    bar.classList.toggle('-below', placed.placement === 'below');
    bar.hidden = false;
    if (opening) { window.requestAnimationFrame(() => this.measureBar()); }
  }

  private measureBar():void {
    const height = this.part('bar').offsetHeight;
    if (height && Math.abs(height - this.barHeight) > 1) {
      this.barHeight = height;
      this.syncBar();
    }
  }

  private hideBar():void {
    this.bar = null;
    this.part('bar').hidden = true;
  }

  private hideBarUnlessFocused():void {
    const bar = this.part('bar');
    if (!bar.contains(bar.ownerDocument.activeElement)) { this.hideBar(); }
  }

  private announce(message:string):void {
    const live = this.part('live');
    live.textContent = '';
    window.requestAnimationFrame(() => { live.textContent = message; });
  }

  private get area():HTMLTextAreaElement { return this.part<HTMLTextAreaElement>('area'); }

  private part<T extends HTMLElement = HTMLElement>(role:string):T {
    return this.root.querySelector<T>(`[data-role="${role}"]`)!;
  }
}
