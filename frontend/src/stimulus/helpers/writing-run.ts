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

export interface WritingEvent {
  seq:number;
  kind:string;
  payload:{ text?:string; message?:string };
}

export interface WritingRunState {
  status:'queued'|'running'|'succeeded'|'failed'|'cancelled';
  error:string|null;
  events:WritingEvent[];
}

export interface WritingTransport {
  create(body:Record<string, unknown>):Promise<{ id:string }>;
  poll(id:string, after:number):Promise<WritingRunState>;
  cancel(id:string):Promise<void>;
}

export interface RunResult {
  status:'succeeded'|'failed'|'cancelled';
  text:string;
  error:string|null;
}

const POLL_MS = 700;
const MAX_POLL_FAILURES = 5;

function csrfHeaders():Record<string, string> {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
  return {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-CSRF-Token': token,
    'X-Requested-With': 'XMLHttpRequest',
  };
}

export function httpTransport(base:string, request:typeof fetch = (...args) => window.fetch(...args)):WritingTransport {
  const send = async <T>(url:string, init:RequestInit):Promise<T> => {
    const response = await request(url, { credentials: 'same-origin', ...init, headers: csrfHeaders() });
    if (!response.ok) { throw new Error(`HTTP ${response.status}`); }
    return (response.status === 204 ? undefined : await response.json()) as T;
  };

  return {
    create: (body) => send(base, { method: 'POST', body: JSON.stringify(body) }),
    poll: (id, after) => send(`${base}/${encodeURIComponent(id)}?after=${after}`, { method: 'GET' }),
    cancel: (id) => send<void>(`${base}/${encodeURIComponent(id)}/cancel`, { method: 'POST', body: '{}' }),
  };
}

// One writing run of the editor's backend, from start to its last event. The stream callback sees
// the text as it grows; stop() ends the run on the server and settles the promise as cancelled.
export class WritingRun {
  private id:string|null = null;
  private stopped = false;
  private wake?:() => void;

  constructor(
    private readonly transport:WritingTransport,
    private readonly onStream:(text:string) => void,
    private readonly pollMs = POLL_MS,
  ) {}

  async execute(body:Record<string, unknown>):Promise<RunResult> {
    let id:string;
    try {
      id = (await this.transport.create(body)).id;
    } catch {
      return { status: this.stopped ? 'cancelled' : 'failed', text: '', error: null };
    }
    this.id = id;
    if (this.stopped) {
      void this.transport.cancel(id).catch(() => undefined);
      return { status: 'cancelled', text: '', error: null };
    }

    let seq = 0;
    let stream = '';
    let failures = 0;
    let reported:string|null = null;

    while (!this.stopped) {
      await this.pause();
      if (this.stopped) { break; }

      let state:WritingRunState;
      try {
        state = await this.transport.poll(id, seq);
      } catch {
        failures += 1;
        if (failures >= MAX_POLL_FAILURES) { return { status: 'failed', text: stream, error: null }; }
        continue;
      }
      failures = 0;
      if (this.stopped) { break; }

      state.events.forEach((event) => {
        seq = Math.max(seq, event.seq);
        if (event.kind === 'text_delta' && event.payload.text) {
          stream += event.payload.text;
        } else if (event.kind === 'completed') {
          stream = event.payload.text ?? stream;
        } else if (event.kind === 'error') {
          reported = event.payload.message ?? null;
        }
      });
      this.onStream(stream);

      if (state.status === 'succeeded') { return { status: 'succeeded', text: stream, error: null }; }
      if (state.status === 'failed') { return { status: 'failed', text: stream, error: state.error ?? reported }; }
      if (state.status === 'cancelled') { return { status: 'cancelled', text: stream, error: null }; }
    }

    return { status: 'cancelled', text: stream, error: null };
  }

  stop():void {
    if (this.stopped) { return; }
    this.stopped = true;
    this.wake?.();
    if (this.id) { void this.transport.cancel(this.id).catch(() => undefined); }
  }

  private pause():Promise<void> {
    return new Promise((resolve) => {
      const timer = window.setTimeout(resolve, this.pollMs);
      this.wake = () => { window.clearTimeout(timer); resolve(); };
    });
  }
}
