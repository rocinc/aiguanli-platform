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

export interface WritingAction {
  id:number;
  label:string;
  template:boolean;
}

export interface WritingBuiltIn {
  key:'continue'|'rewrite'|'acceptance'|'glossary'|'translate'|'write';
  label:string;
}

export type WritingMode = WritingBuiltIn['key']|'revise'|'refine_selection';

export interface WritingMenu {
  enabled:boolean;
  actions:WritingAction[];
  built_in:WritingBuiltIn[];
  glossary:boolean;
}

export interface WritingEvent {
  seq:number;
  kind:'status'|'text_delta'|'completed'|'error';
  payload:{ text?:string; message?:string; status?:string };
}

export interface WritingRunState {
  id:string;
  status:'queued'|'running'|'succeeded'|'failed'|'cancelled';
  error:string|null;
  events:WritingEvent[];
}

// The parts of the CKEditor 5 model API the writing entry uses; the vendor
// bundle ships without typings.
export interface ModelRange { start:unknown; end:unknown; isCollapsed:boolean }
export interface ModelMarker { getRange():ModelRange }
export interface ModelWriter {
  addMarker(name:string, options:{ range:ModelRange; usingOperation:boolean; affectsData:boolean }):ModelMarker;
  removeMarker(name:string):void;
}
export interface WritingModel {
  document:{
    selection:{ getFirstRange():ModelRange|null };
    getRoot():unknown;
  };
  markers:{ get(name:string):ModelMarker|null; has(name:string):boolean };
  change<T>(callback:(writer:ModelWriter) => T):T;
  createRangeIn(element:unknown):ModelRange;
  createRange(start:unknown, end?:unknown):ModelRange;
  getSelectedContent(selection:unknown):unknown;
  insertContent(content:unknown, selectable?:unknown):ModelRange;
}
export interface WritingEditor {
  isReadOnly:boolean;
  model:WritingModel;
  data:{ stringify(fragment:unknown):string; parse(data:string):unknown };
  getData():string;
  editing:{ view:{ focus():void } };
}
