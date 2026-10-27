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
import { renderStreamMessage } from '@hotwired/turbo';
import { announce } from '@primer/live-region-element';

const RECONNECT_MS = [1000, 2000, 5000, 10000];
const FRAME_ID = /^assistant-proposals-meeting-agenda-item-(\d+)$/;

// Frames the server fills later: the proposals under a meeting's agenda
// items. The page listens on a signed stream of its own; a message only
// names one of those frames to reload from its `src`, so no card markup
// ever travels over the cable. After a dropped connection every
// frame is reloaded once, since what was said meanwhile is not replayed.
export default class LiveFramesController extends Controller<HTMLElement> {
  static values = { signedStream: String };

  declare readonly signedStreamValue:string;

  private socket?:WebSocket;
  private reconnects = 0;
  private reconnectTimer?:number;
  private dropped = false;
  private stopped = false;

  connect() {
    this.stopped = false;
    this.openSocket();
  }

  disconnect() {
    this.stopped = true;
    window.clearTimeout(this.reconnectTimer);
    if (this.socket) {
      this.socket.onclose = null;
      this.socket.close();
    }
  }

  private openSocket() {
    if (!this.signedStreamValue || !('WebSocket' in window)) { return; }

    const url = new URL(`${window.appBasePath ?? ''}/cable`, window.location.href);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    const socket = new WebSocket(url.toString(), ['actioncable-v1-json', 'actioncable-unsupported']);
    this.socket = socket;
    const identifier = JSON.stringify({ channel: 'Turbo::StreamsChannel', signed_stream_name: this.signedStreamValue });

    socket.onmessage = (event:MessageEvent<string>) => {
      const data = JSON.parse(event.data) as { type?:string, identifier?:string, message?:unknown };
      if (data.type === 'welcome') {
        socket.send(JSON.stringify({ command: 'subscribe', identifier }));
      } else if (data.type === 'confirm_subscription' && data.identifier === identifier) {
        this.reconnects = 0;
        if (this.dropped) { this.reloadAll(); }
        this.dropped = false;
      } else if (data.type === 'disconnect' || data.type === 'reject_subscription') {
        socket.close();
      } else if (data.identifier === identifier && typeof data.message === 'string') {
        this.receive(data.message);
      }
    };
    socket.onclose = () => {
      if (this.stopped) { return; }

      this.dropped = true;
      const wait = RECONNECT_MS[Math.min(this.reconnects, RECONNECT_MS.length - 1)];
      this.reconnects += 1;
      this.reconnectTimer = window.setTimeout(() => this.openSocket(), wait);
    };
  }

  // Only a replacement of one of our frames by a frame with a src passes.
  private receive(html:string) {
    const template = document.createElement('template');
    template.innerHTML = html;
    const stream = template.content.querySelector('turbo-stream');
    if (stream === null) { return; }

    const target = stream.getAttribute('target');
    if (stream.getAttribute('action') !== 'replace' || !target) { return; }

    const current = document.getElementById(target);
    const next = stream.querySelector('template')?.content.firstElementChild;
    if (!FRAME_ID.test(target) || current?.tagName !== 'TURBO-FRAME') { return; }
    if (next?.tagName !== 'TURBO-FRAME' || next.id !== target || !next.getAttribute('src')) { return; }

    renderStreamMessage(stream.outerHTML);
    this.announceWhenLoaded(target);
  }

  // The frame is swapped in without the person doing anything, so its
  // arrival is said out loud once it has something in it.
  private announceWhenLoaded(id:string) {
    const frame = document.getElementById(id);
    frame?.addEventListener('turbo:frame-load', () => {
      if (frame.querySelector('[data-assistant-signal-id], [data-assistant-action-id]')) {
        void announce(I18n.t('js.assistant_live.new_proposal'), { politeness: 'polite' });
      }
    }, { once: true });
  }

  private reloadAll() {
    document.querySelectorAll<HTMLElement & { reload?:() => void }>('turbo-frame[id^="assistant-proposals-"]').forEach((frame) => {
      const match = FRAME_ID.exec(frame.id);
      if (!match) { return; }

      const src = `${window.appBasePath ?? ''}/assistant/agenda_items/${match[1]}/proposals`;
      frame.setAttribute('src', src);
      frame.reload?.();
    });
  }
}
