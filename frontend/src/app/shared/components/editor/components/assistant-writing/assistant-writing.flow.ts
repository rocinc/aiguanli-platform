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
  canRefineSelection, canUndoRefine, commitEdit, createDraft, currentText, Draft, fitReplacement,
  goToVersion, pushVersion, replaceRange, undoRefine,
} from './assistant-writing.logic';
import { WritingBuiltIn, WritingRunState } from './assistant-writing.types';

export type Phase = 'closed'|'choosing'|'instructing'|'streaming'|'done'|'failed'|'cancelled';
export type Activity = 'generate'|'revise'|'refine';
export type FocusTarget = 'first'|'instruction'|'apply'|'revise'|'draft'|'stop'|'retry'|'editor'|'toggle';

export interface Choice { actionId?:number; builtIn?:WritingBuiltIn['key']; label:string }
export interface Notice { kind:'error'|'info'; text:string }
export interface Captured { input:string; replaceWhole:boolean }

export interface WritingState {
  phase:Phase;
  choice:Choice|null;
  hasSelection:boolean;
  replaceWhole:boolean;
  activity:Activity|null;
  stream:string;
  draft:Draft|null;
  refineRange:{ start:number; end:number }|null;
  caret:number|null;
  notice:Notice|null;
  escArmed:boolean;
  focus:{ target:FocusTarget; n:number }|null;
}

export interface EditorPort {
  capture(choice:Choice):Captured;
  apply(mode:'replace'|'insert', text:string):void;
  release():void;
}

export interface Transport {
  create(body:Record<string, unknown>):Promise<{ id:string }>;
  poll(id:string, after:number):Promise<WritingRunState>;
  cancel(id:string):Promise<void>;
}

export interface FlowEnv {
  editor:EditorPort;
  transport:Transport;
  t(key:string, options?:Record<string, unknown>):string;
  announce(message:string):void;
  scope():Record<string, string>;
  pollMs?:number;
  escMs?:number;
}

const POLL_MS = 700;
const ESC_MS = 3000;
const MAX_POLL_FAILURES = 5;

export function initialState():WritingState {
  return {
    phase: 'closed',
    choice: null,
    hasSelection: false,
    replaceWhole: false,
    activity: null,
    stream: '',
    draft: null,
    refineRange: null,
    caret: null,
    notice: null,
    escArmed: false,
    focus: null,
  };
}

// Where the person is in the loop, and what happens to the work when a run ends. The
// editor component only draws this state and forwards what the person does to it.
export class WritingFlow {
  state:WritingState = initialState();

  private source = '';
  private task = '';
  private runId:string|null = null;
  private seq = 0;
  private failures = 0;
  private epoch = 0;
  private pollTimer?:ReturnType<typeof setTimeout>;
  private escTimer?:ReturnType<typeof setTimeout>;
  private focusCount = 0;
  private lastRun:{ activity:Activity; body:Record<string, unknown>; range:{ start:number; end:number }|null }|null = null;

  constructor(private readonly env:FlowEnv, private readonly onChange:(state:WritingState) => void) {}

  get busy():boolean { return this.state.phase === 'streaming'; }

  get open():boolean { return this.state.phase !== 'closed'; }

  get text():string { return this.state.draft ? currentText(this.state.draft) : ''; }

  openMenu(hasSelection:boolean):void {
    this.set({ phase: 'choosing', hasSelection, notice: null, ...this.focusOn('first') });
  }

  choose(choice:Choice):void {
    const captured = this.env.editor.capture(choice);
    if (!captured.input.trim() && choice.builtIn !== 'write') {
      this.env.editor.release();
      this.set({ phase: 'choosing', notice: { kind: 'info', text: this.env.t('empty') } });
      return;
    }

    this.source = captured.input;
    this.set({
      phase: 'instructing',
      choice,
      replaceWhole: captured.replaceWhole,
      notice: null,
      ...this.focusOn('instruction'),
    });
  }

  back():void {
    this.env.editor.release();
    this.set({ phase: 'choosing', choice: null, notice: null, ...this.focusOn('first') });
  }

  start(instruction:string):boolean {
    const choice = this.state.choice;
    if (!choice) { return false; }

    const text = instruction.trim();
    if (choice.builtIn === 'write' && !text) {
      this.set(this.focusOn('instruction'));
      return false;
    }

    this.task = text;
    void this.execute('generate', {
      input: this.source || text,
      action_id: choice.actionId,
      built_in: choice.builtIn,
      instruction: text || undefined,
      ...this.env.scope(),
    });
    return true;
  }

  revise(opinion:string):boolean {
    const { draft, choice } = this.state;
    const text = opinion.trim();
    if (!draft || !choice || !text || this.busy) { return false; }

    void this.execute('revise', {
      input: this.source || this.task,
      built_in: 'revise',
      base: choice.builtIn,
      action_id: choice.actionId,
      previous: currentText(draft),
      instruction: text,
      task_instruction: this.task || undefined,
      ...this.env.scope(),
    });
    return true;
  }

  refine(start:number, end:number, instruction:string):boolean {
    const { draft } = this.state;
    const text = instruction.trim();
    if (!draft || !text || this.busy) { return false; }

    const whole = currentText(draft);
    if (!canRefineSelection(whole, start, end)) { return false; }

    void this.execute('refine', {
      input: whole,
      built_in: 'refine_selection',
      selection: whole.slice(start, end),
      instruction: text,
      ...this.env.scope(),
    }, { start, end });
    return true;
  }

  edit(text:string):void {
    const { draft } = this.state;
    if (!draft || this.busy) { return; }
    const next = commitEdit(draft, text);
    if (next !== draft) { this.set({ draft: next, notice: null, escArmed: false, caret: null }); }
  }

  goTo(index:number):void {
    const { draft } = this.state;
    if (!draft || this.busy) { return; }
    this.set({ draft: goToVersion(draft, index), notice: null, caret: null });
  }

  step(delta:number):void {
    if (this.state.draft) { this.goTo(this.state.draft.index + delta); }
  }

  undoRefine():boolean {
    const { draft } = this.state;
    if (!draft || this.busy || !canUndoRefine(draft)) { return false; }
    this.set({ draft: undoRefine(draft), notice: null, caret: null, ...this.focusOn('draft') });
    return true;
  }

  async stop():Promise<void> {
    const id = this.runId;
    this.halt();
    if (id) { await this.cancelRun(id); }
    this.settle();
  }

  apply(mode:'replace'|'insert'):void {
    if (!this.state.draft || this.busy) { return; }
    this.env.editor.apply(mode, this.text);
    this.finish('editor');
  }

  discard():void { this.close('editor'); }

  close(target:FocusTarget = 'editor'):void {
    const id = this.busy ? this.runId : null;
    this.halt();
    if (id) { void this.cancelRun(id); }
    this.finish(target);
  }

  // A draft with more than one version took work; one Esc should not throw it away.
  escape():void {
    if (this.state.phase === 'done' && (this.state.draft?.versions.length ?? 0) > 1 && !this.state.escArmed) {
      this.set({ escArmed: true, notice: { kind: 'info', text: this.env.t('leave_confirm') } });
      clearTimeout(this.escTimer);
      this.escTimer = setTimeout(() => {
        if (this.state.escArmed) { this.set({ escArmed: false, notice: null }); }
      }, this.env.escMs ?? ESC_MS);
      return;
    }
    this.close('editor');
  }

  retry():void {
    const last = this.lastRun;
    if (last) { void this.execute(last.activity, last.body, last.range); }
  }

  dispose():void {
    const id = this.busy ? this.runId : null;
    this.halt();
    clearTimeout(this.escTimer);
    if (id) { void this.cancelRun(id); }
    this.env.editor.release();
  }

  private async execute(
    activity:Activity,
    body:Record<string, unknown>,
    range:{ start:number; end:number }|null = null,
  ):Promise<void> {
    this.halt();
    const epoch = this.epoch;
    this.lastRun = { activity, body, range };
    this.seq = 0;
    this.failures = 0;
    this.set({
      phase: 'streaming',
      activity,
      stream: '',
      refineRange: range,
      caret: null,
      notice: null,
      escArmed: false,
      ...this.focusOn('stop'),
    });
    this.env.announce(this.env.t({ generate: 'writing', revise: 'revising', refine: 'refining' }[activity]));

    try {
      const run = await this.env.transport.create(body);
      if (epoch !== this.epoch) {
        void this.cancelRun(run.id);
        return;
      }
      this.runId = run.id;
      this.schedulePoll(epoch);
    } catch {
      if (epoch === this.epoch) { this.fail(null); }
    }
  }

  private schedulePoll(epoch:number):void {
    this.pollTimer = setTimeout(() => { void this.poll(epoch); }, this.env.pollMs ?? POLL_MS);
  }

  private async poll(epoch:number):Promise<void> {
    if (epoch !== this.epoch || !this.runId) { return; }

    try {
      const state = await this.env.transport.poll(this.runId, this.seq);
      if (epoch !== this.epoch) { return; }
      this.failures = 0;
      this.consume(state);
    } catch {
      if (epoch !== this.epoch) { return; }
      this.failures += 1;
      if (this.failures >= MAX_POLL_FAILURES) {
        this.fail(null);
        return;
      }
    }
    if (epoch === this.epoch && this.busy) { this.schedulePoll(epoch); }
  }

  private consume(run:WritingRunState):void {
    let reported = '';
    let stream = this.state.stream;
    run.events.forEach((event) => {
      this.seq = Math.max(this.seq, event.seq);
      if (event.kind === 'text_delta' && event.payload.text) {
        stream += event.payload.text;
      } else if (event.kind === 'completed') {
        stream = event.payload.text ?? stream;
      } else if (event.kind === 'error') {
        reported = event.payload.message ?? '';
      }
    });
    if (stream !== this.state.stream) { this.set({ stream }); }

    if (run.status === 'succeeded') {
      this.succeed(stream);
    } else if (run.status === 'failed') {
      this.fail([run.error, reported].find(Boolean) ?? null);
    } else if (run.status === 'cancelled') {
      this.halt();
      this.settle();
    }
  }

  private succeed(raw:string):void {
    const { activity, draft, refineRange } = this.state;
    const text = raw.trim();
    this.halt();

    if (!text) {
      this.fail(this.env.t('empty_result'), true);
      return;
    }

    if (activity === 'revise' && draft) {
      const next = pushVersion(draft, text, 'revise');
      this.set({ ...this.idle(), draft: next, phase: 'done', ...this.focusOn('revise') });
      this.env.announce(this.env.t('revised', { current: next.index + 1 }));
    } else if (activity === 'refine' && draft && refineRange) {
      const whole = currentText(draft);
      const replacement = fitReplacement(whole.slice(refineRange.start, refineRange.end), text);
      const next = pushVersion(draft, replaceRange(whole, refineRange.start, refineRange.end, replacement), 'refine');
      this.set({
        ...this.idle(),
        draft: next,
        phase: 'done',
        caret: refineRange.start + replacement.length,
        ...this.focusOn('draft'),
      });
      this.env.announce(this.env.t('refined'));
    } else {
      this.set({ ...this.idle(), draft: createDraft(text), phase: 'done', ...this.focusOn('apply') });
      this.env.announce(this.env.t('done', { count: text.length }));
    }
  }

  private fail(message:string|null, plainMessage = false):void {
    this.halt();
    const { activity, draft } = this.state;

    if (draft && activity && activity !== 'generate') {
      const lead = this.env.t(activity === 'revise' ? 'revise_failed' : 'refine_failed');
      this.set({
        ...this.idle(),
        phase: 'done',
        notice: { kind: 'error', text: message && plainMessage ? message : [message, lead].filter(Boolean).join(' ') },
        ...this.focusOn(activity === 'revise' ? 'revise' : 'draft'),
      });
      return;
    }

    this.set({
      phase: 'failed',
      activity: null,
      refineRange: null,
      notice: { kind: 'error', text: message ?? this.env.t('failed') },
      ...this.focusOn('retry'),
    });
  }

  private settle():void {
    this.env.announce(this.env.t('cancelled'));
    if (this.state.draft) {
      this.set({
        ...this.idle(),
        phase: 'done',
        notice: { kind: 'info', text: this.env.t('stopped_kept') },
        ...this.focusOn('revise'),
      });
    } else {
      this.set({ phase: 'cancelled', activity: null, refineRange: null, notice: null, ...this.focusOn('retry') });
    }
  }

  private finish(target:FocusTarget):void {
    this.env.editor.release();
    this.source = '';
    this.task = '';
    this.lastRun = null;
    clearTimeout(this.escTimer);
    this.set({ ...initialState(), ...this.focusOn(target) });
  }

  private idle():Partial<WritingState> {
    return { activity: null, stream: '', refineRange: null, notice: null };
  }

  // Ends whatever run is in flight; late answers from it find a newer epoch and are dropped.
  private halt():void {
    this.epoch += 1;
    clearTimeout(this.pollTimer);
    this.pollTimer = undefined;
    this.runId = null;
  }

  private async cancelRun(id:string):Promise<void> {
    try {
      await this.env.transport.cancel(id);
    } catch {
      // The run stops on its own once nobody reads it; nothing to tell the person.
    }
  }

  private focusOn(target:FocusTarget):{ focus:{ target:FocusTarget; n:number } } {
    this.focusCount += 1;
    return { focus: { target, n: this.focusCount } };
  }

  private set(patch:Partial<WritingState>):void {
    this.state = { ...this.state, ...patch };
    this.onChange(this.state);
  }
}
