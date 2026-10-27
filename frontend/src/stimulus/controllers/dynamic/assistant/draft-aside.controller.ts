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

const DEBOUNCE_MS = 500;

// Points the frame beside a form field at a server-side look at the values
// being typed, so a consequence is told while the person is still deciding.
// The frame stays empty until a field differs from what the form started with.
export default class DraftAsideController extends Controller<HTMLElement> {
  static values = { url: String, fields: Object };

  declare readonly urlValue:string;
  declare readonly fieldsValue:Record<string, string>;

  private form:HTMLFormElement|null = null;
  private initial:Record<string, string> = {};
  private timer?:number;
  private readonly listener = () => this.schedule();

  connect() {
    this.form = this.element.closest('form');
    if (!this.form) { return; }

    this.initial = this.draft();
    this.form.addEventListener('change', this.listener);
    this.form.addEventListener('input', this.listener);
  }

  disconnect() {
    window.clearTimeout(this.timer);
    this.form?.removeEventListener('change', this.listener);
    this.form?.removeEventListener('input', this.listener);
  }

  private schedule() {
    window.clearTimeout(this.timer);
    this.timer = window.setTimeout(() => this.refresh(), DEBOUNCE_MS);
  }

  private refresh() {
    const draft = this.draft();
    const frame = this.element as HTMLElement&{ src?:string|null };

    if (Object.keys(draft).every((key) => draft[key] === this.initial[key])) {
      frame.removeAttribute('src');
      frame.innerHTML = '';
      return;
    }

    frame.src = `${this.urlValue}?${new URLSearchParams(draft).toString()}`;
  }

  private draft():Record<string, string> {
    const form = this.form!;
    return Object.fromEntries(
      Object.entries(this.fieldsValue).map(([param, name]) => {
        const input = form.elements.namedItem(name) as HTMLInputElement|null;
        return [param, input?.value ?? ''];
      }),
    );
  }
}
