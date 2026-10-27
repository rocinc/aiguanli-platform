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
  ChangeDetectionStrategy, ChangeDetectorRef, Component, HostBinding, Input, OnInit, ViewEncapsulation, inject,
} from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { PathHelperService } from 'core-app/core/path-helper/path-helper.service';
import { INotification } from 'core-app/core/state/in-app-notifications/in-app-notification.model';

export interface AssistantNotificationItem {
  headline?:string;
  why?:string;
  settled?:string;
  gone?:string;
  url?:string;
  open_label?:string;
}

@Component({
  selector: 'op-in-app-notification-assistant',
  templateUrl: './in-app-notification-assistant.component.html',
  styleUrls: ['./in-app-notification-assistant.component.sass'],
  changeDetection: ChangeDetectionStrategy.OnPush,
  encapsulation: ViewEncapsulation.None,
  standalone: false,
})
export class InAppNotificationAssistantComponent implements OnInit {
  private http = inject(HttpClient);
  private pathHelper = inject(PathHelperService);
  private cdRef = inject(ChangeDetectorRef);

  @Input() notification:INotification;

  @HostBinding('class.op-ian-assistant') className = true;

  item:AssistantNotificationItem|null = null;

  ngOnInit():void {
    this.http
      .get<AssistantNotificationItem>(`${this.pathHelper.appBasePath}/assistant/notifications/${this.notification.id}.json`)
      .subscribe({
        next: (item) => {
          this.item = item;
          this.cdRef.detectChanges();
        },
        error: () => {
          this.item = null;
        },
      });
  }

  stop(event:Event):void {
    event.stopPropagation();
  }
}
