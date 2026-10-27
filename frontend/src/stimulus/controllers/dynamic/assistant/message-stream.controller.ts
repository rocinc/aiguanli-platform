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

const POLL_MS = 1500;
const SOCKET_GRACE_MS = 3000;
const GIVE_UP_AFTER_MS = 10 * 60 * 1000;
const RECONNECT_MS = [1000, 2000, 5000, 10000];
const SENTENCE_END = /[。！？!?；;]+[”’」』）)"']*|\n+|\.(?=\s)/g;

interface Progress {
  status:'streaming'|'done'|'failed';
  progress?:string|null;
  length:number;
  offset:number;
  content:string;
}

// An answer being written. Text arrives over the conversation's signed
// cable stream as `assistant_message` frames with codepoint offsets; when
// the socket is not there (or drops), the same text is polled from the
// message's JSON from the last offset on. Either way every character is
// placed once, so a reconnect never repeats anything.
export default class MessageStreamController extends Controller<HTMLElement> {
  static values = {
    url: String,
    progressUrl: String,
    signedStream: String,
    length: Number,
  };

  static targets = ['content', 'status'];

  declare readonly urlValue:string;
  declare readonly progressUrlValue:string;
  declare readonly signedStreamValue:string;
  declare readonly lengthValue:number;
  declare readonly contentTarget:HTMLElement;
  declare readonly hasStatusTarget:boolean;
  declare readonly statusTarget:HTMLElement;

  private received = 0;
  private pending = '';
  private socket?:WebSocket;
  private subscribed = false;
  private reconnects = 0;
  private pollTimer?:number;
  private graceTimer?:number;
  private reconnectTimer?:number;
  private startedAt = Date.now();
  private settling = false;
  private stopped = false;
  private abortController = new AbortController();

  connect() {
    this.received = this.lengthValue;
    this.graceTimer = window.setTimeout(() => this.startPolling(), SOCKET_GRACE_MS);
    this.openSocket();
  }

  disconnect() {
    this.stop();
  }

  private stop() {
    this.stopped = true;
    window.clearTimeout(this.pollTimer);
    window.clearTimeout(this.graceTimer);
    window.clearTimeout(this.reconnectTimer);
    this.abortController.abort();
    if (this.socket) {
      this.socket.onclose = null;
      this.socket.close();
    }
  }

  // The Action Cable protocol, just what one subscription needs.
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
        this.subscribed = true;
        this.reconnects = 0;
        window.clearTimeout(this.graceTimer);
        this.stopPolling();
        // Whatever was written while nobody listened.
        void this.catchUp();
      } else if (data.type === 'disconnect' || data.type === 'reject_subscription') {
        socket.close();
      } else if (data.identifier === identifier && typeof data.message === 'string') {
        this.receive(data.message);
      }
    };
    socket.onclose = () => {
      this.subscribed = false;
      if (this.stopped) { return; }

      this.startPolling();
      const wait = RECONNECT_MS[Math.min(this.reconnects, RECONNECT_MS.length - 1)];
      this.reconnects += 1;
      this.reconnectTimer = window.setTimeout(() => this.openSocket(), wait);
    };
  }

  private receive(html:string) {
    const template = document.createElement('template');
    template.innerHTML = html;
    const stream = template.content.querySelector('turbo-stream[action="assistant_message"]');
    if (stream?.getAttribute('target') !== this.element.id) { return; }

    const text = stream.querySelector('template')?.content.textContent ?? '';
    switch (stream.getAttribute('kind')) {
      case 'delta':
        this.placeAt(parseInt(stream.getAttribute('from') ?? '0', 10), text);
        break;
      case 'status':
        this.showStatus(text);
        break;
      case 'settled':
        void this.settle();
        break;
      default:
        break;
    }
  }

  private placeAt(from:number, text:string) {
    const chars = Array.from(text);
    const to = from + chars.length;
    if (to <= this.received) { return; }
    if (from > this.received) {
      void this.catchUp();
      return;
    }
    this.enqueue(chars.slice(this.received - from));
  }

  private enqueue(chars:string[]) {
    if (chars.length === 0) { return; }

    this.received += chars.length;
    this.pending += chars.join('');
    this.reveal();
  }

  private reveal() {
    let end = 0;
    for (const match of this.pending.matchAll(SENTENCE_END)) {
      end = match.index + match[0].length;
    }
    if (end === 0) { return; }

    const sentence = document.createElement('span');
    sentence.classList.add('assistant-message--sentence');
    sentence.textContent = this.pending.slice(0, end);
    this.pending = this.pending.slice(end);
    this.contentTarget.append(sentence);
  }

  private showStatus(text:string) {
    if (!this.hasStatusTarget || !text) { return; }

    const label = this.statusTarget.querySelector('[data-assistant-progress]');
    if (label && label.textContent !== text) {
      label.textContent = text;
      // The message is aria-busy while it streams, so nothing inside it is
      // read; the step it is on is said on its own.
      void announce(text, { politeness: 'polite' });
    }
  }

  private startPolling() {
    if (this.stopped || this.subscribed || this.pollTimer) { return; }

    this.pollTimer = window.setTimeout(() => { void this.poll(); }, POLL_MS);
  }

  private stopPolling() {
    window.clearTimeout(this.pollTimer);
    this.pollTimer = undefined;
  }

  private async poll() {
    this.pollTimer = undefined;
    if (Date.now() - this.startedAt > GIVE_UP_AFTER_MS) {
      this.stop();
      return;
    }
    await this.catchUp();
    this.startPolling();
  }

  private async catchUp() {
    if (this.settling || this.stopped) { return; }

    try {
      const url = new URL(this.progressUrlValue, window.location.href);
      url.searchParams.set('offset', String(this.received));
      const response = await fetch(url.toString(), {
        headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
        credentials: 'same-origin',
        signal: this.abortController.signal,
      });
      if (!response.ok) { return; }

      const progress = await response.json() as Progress;
      if (progress.progress) { this.showStatus(progress.progress); }
      this.placeAt(progress.offset, progress.content ?? '');
      if (progress.status !== 'streaming') { await this.settle(); }
    } catch (error) {
      if ((error as Error).name === 'AbortError') { return; }
    }
  }

  // The final answer is rendered by the server (formatting, cards); it
  // replaces the message in place once the letters have caught up.
  private async settle() {
    if (this.settling) { return; }

    this.settling = true;
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: 'text/html', 'X-Requested-With': 'XMLHttpRequest' },
        credentials: 'same-origin',
        signal: this.abortController.signal,
      });
      if (!response.ok) { this.settling = false; return; }

      const template = document.createElement('template');
      template.innerHTML = (await response.text()).trim();
      const next = template.content.firstElementChild as HTMLElement|null;
      if (!next || next.getAttribute('aria-busy') === 'true') {
        this.settling = false;
        return;
      }

      const host = this.element.closest('[data-controller~="assistant--panel"]');
      this.stop();
      this.element.replaceWith(next);
      host?.dispatchEvent(new CustomEvent('assistant:message-settled'));
    } catch (error) {
      if ((error as Error).name !== 'AbortError') { this.settling = false; }
    }
  }
}
