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
import { getMetaContent } from 'core-app/core/setup/globals/global-helpers';

const DWELL_MS = 5000;

// Tells the assistant this person had the page's object in front of them for
// a while, so it does not tell them what they have already seen (02 §1.1).
// Sent once per page load; a lost beacon costs nothing.
export default class BeaconController extends Controller<HTMLElement> {
  static values = { url: String, type: String, id: Number };

  declare readonly urlValue:string;
  declare readonly typeValue:string;
  declare readonly idValue:number;

  private timer?:number;
  private sent = false;
  private abortController = new AbortController();

  connect() {
    document.addEventListener('visibilitychange', this.visibilityChanged, { signal: this.abortController.signal });
    this.visibilityChanged();
  }

  disconnect() {
    window.clearTimeout(this.timer);
    this.abortController.abort();
  }

  private visibilityChanged = () => {
    window.clearTimeout(this.timer);
    if (this.sent || document.hidden) { return; }

    this.timer = window.setTimeout(() => this.send(), DWELL_MS);
  };

  private send() {
    if (this.sent || document.hidden) { return; }
    this.sent = true;

    const body = new URLSearchParams({ type: this.typeValue, id: String(this.idValue) });
    void fetch(this.urlValue, {
      method: 'POST',
      body,
      keepalive: true,
      credentials: 'same-origin',
      headers: { 'X-CSRF-Token': getMetaContent('csrf-token'), 'X-Requested-With': 'XMLHttpRequest' },
    }).catch(() => undefined);
  }
}
