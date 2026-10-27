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
  ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, input, OnDestroy, OnInit, signal, untracked, viewChild,
} from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';
import { SparkleFillIconComponent, StopIconComponent } from '@openproject/octicons-angular';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { PathHelperService } from 'core-app/core/path-helper/path-helper.service';
import { getMetaValue } from 'core-app/core/setup/globals/global-helpers';
import idFromLink from 'core-app/features/hal/helpers/id-from-link';
import { generateId } from 'core-app/shared/helpers/dom-helpers';
import { ICKEditorContext, ICKEditorInstance } from 'core-app/shared/components/editor/components/ckeditor/ckeditor.types';
import {
  Captured, Choice, EditorPort, FocusTarget, initialState, Transport, WritingFlow, WritingState,
} from './assistant-writing.flow';
import {
  canRefineSelection, canUndoRefine, clampAnchor, currentText, isSubmitKey, measureTextareaRange, placeBar,
} from './assistant-writing.logic';
import {
  WritingAction, WritingBuiltIn, WritingEditor, WritingMenu, WritingRunState,
} from './assistant-writing.types';

interface BarView { start:number; end:number; left:number; top:number; width:number; placement:'above'|'below' }

const MARKER = 'assistant-writing';
const INSERT_ONLY = ['continue', 'acceptance'];
const BAR_WIDTH = 320;
const BAR_GUTTER = 8;
const BAR_HEIGHT_GUESS = 84;
const SWAP_MS = 180;
// Fields that are documents rather than conversations (S1.1): the work package
// description, a wiki page, news, a document, the project status, meeting notes.
const DOCUMENT_FIELD = /^(description|work_package\[description\]|page\[text\]|news\[description\]|document\[description\]|project\[status_explanation\]|meeting_(agenda_item|outcome)\b.*\[notes\])$/;

const TEXT_KEYS = [
  'toggle', 'menu', 'built_in', 'configured', 'glossary', 'on_selection', 'on_everything',
  'instruction_label', 'request_label', 'instruction_hint', 'instruction_hint_write', 'instruction_placeholder',
  'placeholder_continue', 'placeholder_rewrite', 'placeholder_translate', 'placeholder_acceptance',
  'placeholder_glossary', 'placeholder_action',
  'start', 'back', 'preview', 'draft', 'draft_hint', 'writing', 'revising', 'refining', 'stop',
  'replace_selection', 'replace_all', 'insert', 'discard', 'retry', 'close', 'cancelled', 'empty', 'failed', 'template',
  'versions', 'prev_version', 'next_version', 'revise_label', 'revise_placeholder', 'revise_start',
  'refine_label', 'refine_placeholder', 'refine_start', 'chip_shorter', 'chip_specific', 'chip_rephrase', 'chip_formal',
  'refined', 'undo_refine',
] as const;
type TextKey = typeof TEXT_KEYS[number];

const PLACEHOLDER_KEYS:Record<string, TextKey> = {
  continue: 'placeholder_continue',
  rewrite: 'placeholder_rewrite',
  translate: 'placeholder_translate',
  acceptance: 'placeholder_acceptance',
  glossary: 'placeholder_glossary',
  write: 'instruction_placeholder',
};

// The editor's writing entry (04 G3), next to the editor rather than in its
// toolbar, since the CKEditor build is precompiled. The text being worked on
// is held by a model marker, so it can still be replaced after the person
// typed elsewhere while the assistant was writing. What the assistant wrote
// is a draft the person goes on working on; the steps live in WritingFlow.
@Component({
  selector: 'op-assistant-writing',
  templateUrl: './assistant-writing.component.html',
  styleUrls: ['./assistant-writing.component.sass'],
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [SparkleFillIconComponent, StopIconComponent],
})
export class AssistantWritingComponent implements OnInit, OnDestroy {
  private static menus = new Map<string, Promise<WritingMenu|null>>();

  readonly editor = input.required<ICKEditorInstance>();
  readonly context = input<ICKEditorContext>();

  private readonly http = inject(HttpClient);
  private readonly I18n = inject(I18nService);
  private readonly pathHelper = inject(PathHelperService);

  private readonly toggleButton = viewChild<ElementRef<HTMLButtonElement>>('toggleButton');
  private readonly panel = viewChild<ElementRef<HTMLElement>>('panel');
  private readonly instructionInput = viewChild<ElementRef<HTMLTextAreaElement>>('instruction');
  private readonly draftArea = viewChild<ElementRef<HTMLTextAreaElement>>('draft');
  private readonly reviseInput = viewChild<ElementRef<HTMLInputElement>>('reviseInput');
  private readonly barElement = viewChild<ElementRef<HTMLElement>>('barElement');

  readonly menu = signal<WritingMenu|null>(null);
  readonly state = signal<WritingState>(initialState());
  readonly bar = signal<BarView|null>(null);
  readonly swapping = signal(false);
  readonly announcement = signal('');

  readonly phase = computed(() => this.state().phase);
  readonly open = computed(() => this.phase() !== 'closed');
  readonly busy = computed(() => this.phase() === 'streaming');
  readonly choice = computed(() => this.state().choice);
  readonly notice = computed(() => this.state().notice);
  readonly draftText = computed(() => {
    const draft = this.state().draft;
    return draft ? currentText(draft) : '';
  });

  readonly versionCount = computed(() => this.state().draft?.versions.length ?? 0);
  readonly versionIndex = computed(() => this.state().draft?.index ?? 0);
  readonly versionLabel = computed(() => `${this.versionIndex() + 1}/${this.versionCount()}`);
  readonly canUndo = computed(() => canUndoRefine(this.state().draft));

  readonly segments = computed(() => {
    const { refineRange, draft, stream } = this.state();
    if (!refineRange || !draft || this.phase() !== 'streaming') { return null; }
    const whole = currentText(draft);
    return {
      before: whole.slice(0, refineRange.start),
      marked: stream || whole.slice(refineRange.start, refineRange.end),
      after: whole.slice(refineRange.end),
      waiting: !stream,
    };
  });

  readonly canReplace = computed(() => {
    const builtIn = this.choice()?.builtIn;
    if (INSERT_ONLY.includes(builtIn ?? '')) { return false; }
    return builtIn !== 'write' || this.state().hasSelection;
  });

  readonly replaceLabel = computed(() => (this.state().replaceWhole ? this.text.replace_all : this.text.replace_selection));
  readonly isWrite = computed(() => this.choice()?.builtIn === 'write');
  readonly placeholder = computed(() => this.text[PLACEHOLDER_KEYS[this.choice()?.builtIn ?? ''] ?? 'placeholder_action']);
  readonly statusText = computed(() => {
    const activity = this.state().activity;
    if (activity === 'revise') { return this.text.revising; }
    return activity === 'refine' ? this.text.refining : this.text.writing;
  });

  readonly chips = [this.t('chip_shorter'), this.t('chip_specific'), this.t('chip_rephrase'), this.t('chip_formal')];

  readonly ids = {
    panel: generateId('assistant-writing-panel'),
    preview: generateId('assistant-writing-preview'),
    instruction: generateId('assistant-writing-instruction'),
    revise: generateId('assistant-writing-revise'),
  };

  readonly text = Object.fromEntries(TEXT_KEYS.map((key) => [key, this.t(key)])) as Record<TextKey, string>;

  private readonly flow = new WritingFlow({
    editor: this.editorPort(),
    transport: this.transport(),
    t: (key, options) => this.t(key, options),
    announce: (message) => this.announce(message),
    scope: () => this.scope,
  }, (state) => {
    this.state.set(state);
    if (state.phase !== 'done') { this.bar.set(null); }
  });

  private barHeight = BAR_HEIGHT_GUESS;
  private composing = false;

  constructor() {
    effect(() => {
      const focus = this.state().focus;
      if (focus) { untracked(() => this.focusOn(focus.target)); }
    });
  }

  ngOnInit():void {
    if (!DOCUMENT_FIELD.test(this.context()?.field ?? '')) { return; }

    void this.loadMenu().then((menu) => this.menu.set(menu?.enabled ? menu : null));
  }

  ngOnDestroy():void {
    this.flow.dispose();
  }

  toggle():void {
    if (this.writingEditor.isReadOnly) { return; }
    if (this.flow.open) {
      this.flow.close('toggle');
    } else {
      this.flow.openMenu(this.selectionRange() !== null);
    }
  }

  chooseAction(action:WritingAction):void { this.flow.choose({ actionId: action.id, label: action.label }); }

  chooseBuiltIn(builtIn:WritingBuiltIn):void { this.flow.choose({ builtIn: builtIn.key, label: builtIn.label }); }

  back():void { this.flow.back(); }

  instructionKeydown(event:KeyboardEvent, field:HTMLTextAreaElement):void {
    if (isSubmitKey(event)) {
      event.preventDefault();
      this.flow.start(field.value);
    }
  }

  start(field:HTMLTextAreaElement):void { this.flow.start(field.value); }

  reviseKeydown(event:KeyboardEvent, field:HTMLInputElement):void {
    if (isSubmitKey(event)) {
      event.preventDefault();
      this.submitRevise(field);
    }
  }

  submitRevise(field:HTMLInputElement):void {
    if (this.flow.revise(field.value)) { field.value = ''; }
  }

  step(delta:number):void {
    this.flow.step(delta);
    this.swapping.set(true);
    window.setTimeout(() => this.swapping.set(false), SWAP_MS);
  }

  undoRefine():void { this.flow.undoRefine(); }

  stop():void { void this.flow.stop(); }

  apply(mode:'replace'|'insert'):void { this.flow.apply(mode); }

  discard():void { this.flow.discard(); }

  close():void { this.flow.close(); }

  retry():void { this.flow.retry(); }

  panelKeydown(event:KeyboardEvent):void {
    if (event.key !== 'Escape') { return; }
    event.preventDefault();
    event.stopPropagation();
    if (this.bar()) {
      this.closeBar();
    } else {
      this.flow.escape();
    }
  }

  onDraftInput(event:Event):void {
    if (this.composing) { return; }
    this.flow.edit((event.target as HTMLTextAreaElement).value);
    this.syncBar();
  }

  onCompositionStart():void { this.composing = true; }

  onCompositionEnd(event:Event):void {
    this.composing = false;
    this.flow.edit((event.target as HTMLTextAreaElement).value);
  }

  draftKeydown(event:KeyboardEvent):void {
    if (event.key.toLowerCase() === 'z' && (event.ctrlKey || event.metaKey) && !event.shiftKey && this.canUndo()) {
      event.preventDefault();
      this.flow.undoRefine();
    }
  }

  draftBlur(event:FocusEvent):void {
    const next = event.relatedTarget as Node|null;
    if (next && this.barElement()?.nativeElement.contains(next)) { return; }
    this.bar.set(null);
  }

  syncBar():void {
    const area = this.draftArea()?.nativeElement;
    const panel = this.panel()?.nativeElement;
    if (!area || !panel || this.phase() !== 'done') {
      this.bar.set(null);
      return;
    }

    const { selectionStart: start, selectionEnd: end } = area;
    if (!canRefineSelection(area.value, start, end)) {
      if (!this.barHasFocus()) { this.bar.set(null); }
      return;
    }

    const anchor = clampAnchor(measureTextareaRange(area, start, end), area.getBoundingClientRect());
    if (!anchor) {
      this.bar.set(null);
      return;
    }

    const box = panel.getBoundingClientRect();
    const width = Math.min(BAR_WIDTH, box.width - 2 * BAR_GUTTER);
    const placed = placeBar(anchor, { width, height: this.barHeight }, { left: box.left + BAR_GUTTER, right: box.right - BAR_GUTTER });
    const opening = this.bar() === null;
    this.bar.set({
      start, end, width, placement: placed.placement, left: placed.left - box.left, top: placed.top - box.top,
    });
    if (opening) { window.requestAnimationFrame(() => this.measureBar()); }
  }

  barKeydown(event:KeyboardEvent, field:HTMLInputElement):void {
    if (isSubmitKey(event)) {
      event.preventDefault();
      this.refineFromBar(field.value);
    } else if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      this.closeBar();
    }
  }

  barMousedown(event:MouseEvent):void {
    if (!(event.target instanceof HTMLInputElement)) { event.preventDefault(); }
  }

  refineFromBar(instruction:string):void {
    const bar = this.bar();
    if (bar) { this.flow.refine(bar.start, bar.end, instruction); }
  }

  private closeBar():void {
    const bar = this.bar();
    this.bar.set(null);
    const area = this.draftArea()?.nativeElement;
    if (bar && area) {
      area.focus({ preventScroll: true });
      area.setSelectionRange(bar.start, bar.end);
    }
  }

  private barHasFocus():boolean {
    const element = this.barElement()?.nativeElement;
    return !!element && element.contains(element.ownerDocument.activeElement);
  }

  private measureBar():void {
    const height = this.barElement()?.nativeElement.offsetHeight;
    if (height && Math.abs(height - this.barHeight) > 1) {
      this.barHeight = height;
      this.syncBar();
    }
  }

  private focusOn(target:FocusTarget):void {
    window.requestAnimationFrame(() => {
      const panel = this.panel()?.nativeElement;
      switch (target) {
        case 'first': panel?.querySelector<HTMLElement>('button')?.focus(); break;
        case 'instruction': this.instructionInput()?.nativeElement.focus(); break;
        case 'apply': panel?.querySelector<HTMLElement>('[data-writing-apply]')?.focus(); break;
        case 'stop': panel?.querySelector<HTMLElement>('[data-writing-stop]')?.focus(); break;
        case 'retry': panel?.querySelector<HTMLElement>('[data-writing-retry]')?.focus(); break;
        case 'revise': this.reviseInput()?.nativeElement.focus(); break;
        case 'draft': this.focusDraft(); break;
        case 'toggle': this.toggleButton()?.nativeElement.focus(); break;
        default: this.writingEditor.editing.view.focus();
      }
    });
  }

  private focusDraft():void {
    const area = this.draftArea()?.nativeElement;
    if (!area) { return; }

    area.focus({ preventScroll: true });
    const caret = this.state().caret;
    if (caret === null) { return; }

    area.setSelectionRange(caret, caret);
    const spot = measureTextareaRange(area, Math.max(0, caret - 1), caret);
    const box = area.getBoundingClientRect();
    if (spot.bottom > box.bottom - BAR_GUTTER || spot.top < box.top) {
      area.scrollTop += spot.top - box.top - box.height / 3;
    }
  }

  private editorPort():EditorPort {
    return {
      capture: (choice) => this.captureInput(choice),
      apply: (mode, text) => this.applyToEditor(mode, text),
      release: () => this.clearMarker(),
    };
  }

  private transport():Transport {
    return {
      create: (body) => firstValueFrom(this.http.post<{ id:string }>(this.writingsPath, body)),
      poll: (id, after) => firstValueFrom(this.http.get<WritingRunState>(
        `${this.writingsPath}/${encodeURIComponent(id)}`,
        { params: { after: String(after) } },
      )),
      cancel: (id) => firstValueFrom(this.http.post(`${this.writingsPath}/${encodeURIComponent(id)}/cancel`, {})).then(() => undefined),
    };
  }

  private applyToEditor(mode:'replace'|'insert', text:string):void {
    const editor = this.writingEditor;
    if (editor.isReadOnly) { return; }
    const marker = editor.model.markers.get(MARKER);
    const content = editor.data.parse(text);

    editor.model.change(() => {
      if (mode === 'replace' && marker) {
        editor.model.insertContent(content, marker.getRange());
      } else if (marker) {
        editor.model.insertContent(content, editor.model.createRange(marker.getRange().end));
      } else {
        editor.model.insertContent(content);
      }
    });
  }

  // What the assistant works on: the selection if there is one, otherwise
  // the whole text, which a result may then replace as a whole. Continuing
  // reads everything and writes after the selection or at the end; writing
  // from an instruction goes where the caret is.
  private captureInput(choice:Choice):Captured {
    const editor = this.writingEditor;
    const model = editor.model;
    const selected = this.selectionRange();
    const whole = model.createRangeIn(model.document.getRoot());
    const caret = model.document.selection.getFirstRange() ?? whole;

    let target = selected ?? whole;
    if (choice.builtIn === 'write' && !selected) { target = caret; }

    model.change((writer) => {
      if (model.markers.has(MARKER)) { writer.removeMarker(MARKER); }
      writer.addMarker(MARKER, { range: target, usingOperation: false, affectsData: false });
    });

    const selectedText = selected ? editor.data.stringify(model.getSelectedContent(model.document.selection)) : '';
    let input = selectedText;
    if (choice.builtIn !== 'write' && (INSERT_ONLY.includes(choice.builtIn ?? '') || !selected)) { input = editor.getData(); }
    return { input, replaceWhole: !selected && !choice.builtIn };
  }

  private selectionRange() {
    const range = this.writingEditor.model.document.selection.getFirstRange();
    return range && !range.isCollapsed ? range : null;
  }

  private clearMarker():void {
    const editor = this.writingEditor;
    if (!editor?.model?.markers.has(MARKER)) { return; }
    editor.model.change((writer) => writer.removeMarker(MARKER));
  }

  private announce(message:string):void {
    this.announcement.set('');
    window.requestAnimationFrame(() => this.announcement.set(message));
  }

  private loadMenu():Promise<WritingMenu|null> {
    const params = this.scope;
    const key = `${params.project_id ?? ''}|${params.type_id ?? ''}`;
    let menu = AssistantWritingComponent.menus.get(key);
    if (!menu) {
      menu = firstValueFrom(this.http.get<WritingMenu>(this.writingsPath, { params }))
        .catch(() => null);
      AssistantWritingComponent.menus.set(key, menu);
    }
    return menu;
  }

  private get scope():Record<string, string> {
    const projectId = getMetaValue('current_project', 'projectId', null);
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment,@typescript-eslint/no-unsafe-member-access
    const typeHref:string|undefined = this.context()?.resource?.$links?.type?.href;
    const scope:Record<string, string> = {};
    if (projectId) { scope.project_id = projectId; }
    if (typeHref) { scope.type_id = idFromLink(typeHref); }
    return scope;
  }

  private get writingsPath():string {
    return `${this.pathHelper.appBasePath}/assistant/writings`;
  }

  private get writingEditor():WritingEditor {
    return this.editor() as unknown as WritingEditor;
  }

  versionAria():string {
    return this.t('version_position', { current: this.versionIndex() + 1, total: this.versionCount() });
  }

  private t(key:string, options:Record<string, unknown> = {}):string {
    return this.I18n.t(`js.assistant_writing.${key}`, options);
  }
}
