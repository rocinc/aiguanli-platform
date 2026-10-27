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

export type VersionSource = 'generated'|'revise'|'refine'|'edit';

export interface Version { text:string; source:VersionSource }

export interface Draft { versions:Version[]; index:number }

export interface Rect { left:number; top:number; right:number; bottom:number; width:number; height:number }

export interface Placement { left:number; top:number; placement:'above'|'below' }

export function createDraft(text:string):Draft {
  return { versions: [{ text, source: 'generated' }], index: 0 };
}

export function currentVersion(draft:Draft):Version {
  return draft.versions[draft.index];
}

export function currentText(draft:Draft):string {
  return currentVersion(draft).text;
}

export function pushVersion(draft:Draft, text:string, source:VersionSource):Draft {
  const versions = [...draft.versions, { text, source }];
  return { versions, index: versions.length - 1 };
}

// Typing is one version, not one per keystroke: edits made on the newest hand-edited
// version go into it, anything else starts a new one.
export function commitEdit(draft:Draft, text:string):Draft {
  const current = currentVersion(draft);
  if (text === current.text) { return draft; }

  const last = draft.versions.length - 1;
  if (current.source === 'edit' && draft.index === last) {
    const versions = draft.versions.slice();
    versions[last] = { text, source: 'edit' };
    return { versions, index: last };
  }
  return pushVersion(draft, text, 'edit');
}

export function goToVersion(draft:Draft, index:number):Draft {
  const clamped = Math.max(0, Math.min(draft.versions.length - 1, index));
  return clamped === draft.index ? draft : { versions: draft.versions, index: clamped };
}

export function canUndoRefine(draft:Draft|null):boolean {
  return !!draft && draft.versions.length > 1
    && draft.index === draft.versions.length - 1
    && currentVersion(draft).source === 'refine';
}

export function undoRefine(draft:Draft):Draft {
  if (!canUndoRefine(draft)) { return draft; }
  const versions = draft.versions.slice(0, -1);
  return { versions, index: versions.length - 1 };
}

export function canRefineSelection(text:string, start:number, end:number):boolean {
  return end - start >= 2 && /\S/.test(text.slice(start, end));
}

export function replaceRange(text:string, start:number, end:number, replacement:string):string {
  return text.slice(0, start) + replacement + text.slice(end);
}

const QUOTE_PAIRS:[string, string][] = [['"', '"'], ['“', '”'], ['「', '」'], ['『', '』'], ['‘', '’'], ["'", "'"]];

// The replacement takes over the passage's own leading and trailing whitespace, so the
// paragraph breaks around it stay as they were, and loses quotes the model wrapped it in.
export function fitReplacement(selected:string, replacement:string):string {
  const lead = /^\s*/.exec(selected)![0];
  const trail = /\s*$/.exec(selected)![0];
  let core = replacement.trim();
  const original = selected.trim();

  QUOTE_PAIRS.forEach(([open, close]) => {
    if (core.length > 2 && core.startsWith(open) && core.endsWith(close) && !original.startsWith(open)) {
      core = core.slice(open.length, core.length - close.length).trim();
    }
  });
  return lead + core + trail;
}

export interface KeyLike {
  key:string;
  shiftKey?:boolean;
  isComposing?:boolean;
  keyCode?:number;
}

// Enter confirms; Shift+Enter is a line break. Enter that commits an IME candidate
// (Chinese input) is not a confirmation.
export function isSubmitKey(event:KeyLike):boolean {
  return event.key === 'Enter' && !event.shiftKey && !event.isComposing && event.keyCode !== 229;
}

export function clampAnchor(anchor:Rect, visible:Rect):Rect|null {
  if (anchor.bottom < visible.top || anchor.top > visible.bottom) { return null; }

  const top = Math.max(anchor.top, visible.top);
  const bottom = Math.min(anchor.bottom, visible.bottom);
  const left = Math.max(anchor.left, visible.left);
  const right = Math.max(left, Math.min(anchor.right, visible.right));
  return { left, right, top, bottom, width: right - left, height: bottom - top };
}

// Above the anchor, or below it when there is no room above; kept inside the bounds
// sideways. All rectangles are in viewport coordinates.
export function placeBar(
  anchor:Rect,
  size:{ width:number; height:number },
  bounds:{ left:number; right:number },
  viewportTop = 0,
  gap = 6,
):Placement {
  const centered = anchor.left + anchor.width / 2 - size.width / 2;
  const left = Math.max(bounds.left, Math.min(centered, bounds.right - size.width));
  const above = anchor.top - size.height - gap;
  return above >= viewportTop
    ? { left, top: above, placement: 'above' }
    : { left, top: anchor.bottom + gap, placement: 'below' };
}

const MIRRORED_STYLES = [
  'boxSizing', 'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
  'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
  'fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'fontVariant', 'fontStretch',
  'lineHeight', 'letterSpacing', 'wordSpacing', 'tabSize', 'textIndent', 'textTransform',
  'overflowWrap', 'wordBreak', 'textAlign',
] as const;

// A textarea has no Range of its own. The same text laid out in an invisible div of the
// same width and font has one, and its rectangle is the selection's, in viewport
// coordinates and corrected for the textarea's scroll.
export function measureTextareaRange(textarea:HTMLTextAreaElement, start:number, end:number):Rect {
  const doc = textarea.ownerDocument;
  const view = doc.defaultView!;
  const style = view.getComputedStyle(textarea);
  const mirror = doc.createElement('div');

  MIRRORED_STYLES.forEach((property) => {
    (mirror.style as unknown as Record<string, string>)[property] = style[property];
  });
  mirror.style.position = 'absolute';
  mirror.style.visibility = 'hidden';
  mirror.style.pointerEvents = 'none';
  mirror.style.top = '0';
  mirror.style.left = '0';
  mirror.style.height = 'auto';
  mirror.style.whiteSpace = 'pre-wrap';
  mirror.style.boxSizing = 'border-box';
  mirror.style.width = `${textarea.clientWidth + parseFloat(style.borderLeftWidth || '0') + parseFloat(style.borderRightWidth || '0')}px`;

  const text = doc.createTextNode(textarea.value);
  mirror.appendChild(text);
  doc.body.appendChild(mirror);

  try {
    const range = doc.createRange();
    range.setStart(text, Math.min(start, text.length));
    range.setEnd(text, Math.min(end, text.length));
    const selected = range.getBoundingClientRect();
    const origin = mirror.getBoundingClientRect();
    const box = textarea.getBoundingClientRect();

    const left = box.left + (selected.left - origin.left) - textarea.scrollLeft;
    const top = box.top + (selected.top - origin.top) - textarea.scrollTop;
    return { left, top, right: left + selected.width, bottom: top + selected.height, width: selected.width, height: selected.height };
  } finally {
    mirror.remove();
  }
}
