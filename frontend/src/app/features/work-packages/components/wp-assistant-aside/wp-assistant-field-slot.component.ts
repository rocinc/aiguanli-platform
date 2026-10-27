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

import { ChangeDetectionStrategy, ChangeDetectorRef, Component, HostBinding, Input, OnInit, inject } from '@angular/core';
import { filter } from 'rxjs/operators';
import { PathHelperService } from 'core-app/core/path-helper/path-helper.service';
import { WorkPackageResource } from 'core-app/features/hal/resources/work-package-resource';
import { HalEventsService } from 'core-app/features/hal/services/hal-events.service';
import { UntilDestroyedMixin } from 'core-app/shared/helpers/angular/until-destroyed.mixin';
import isNewResource from 'core-app/features/hal/helpers/is-new-resource';

export const ASSISTANT_FIELD_SLOTS = ['date', 'assignee', 'status', 'version', 'estimatedTime', 'remainingTime'];
const PROMISE_SLOT = 'date';

@Component({
  selector: 'op-wp-assistant-field-slot',
  template: '<turbo-frame [id]="frameId" class="hide-when-print" [attr.src]="src"></turbo-frame>',
  changeDetection: ChangeDetectionStrategy.OnPush,
  standalone: false,
})
export class WorkPackageAssistantFieldSlotComponent extends UntilDestroyedMixin implements OnInit {
  @Input() workPackage:WorkPackageResource;

  @Input() fieldName:string;

  src:string|null = null;

  private readonly pathHelper = inject(PathHelperService);
  private readonly halEvents = inject(HalEventsService);
  private readonly cdRef = inject(ChangeDetectorRef);

  private refreshes = 0;

  @HostBinding('attr.data-assistant-field')
  get slot():string|null {
    return this.supported ? this.fieldName : null;
  }

  get frameId():string {
    return `assistant-wp-field-aside-${this.fieldName}`;
  }

  ngOnInit():void {
    if (!this.supported || isNewResource(this.workPackage)) {
      return;
    }

    if (this.fieldName === PROMISE_SLOT) {
      this.show();
    }

    this.halEvents.events$
      .pipe(
        this.untilDestroyed(),
        filter((event) => event.resourceType === 'WorkPackage' && event.eventType === 'updated' && event.id === this.workPackage.id),
      )
      .subscribe(() => this.show());
  }

  private get supported():boolean {
    return ASSISTANT_FIELD_SLOTS.includes(this.fieldName);
  }

  private show():void {
    this.refreshes += 1;
    this.src = `${this.pathHelper.staticBase}/assistant/work_packages/${this.workPackage.id}/field_aside?field=${this.fieldName}&refresh=${this.refreshes}`;
    this.cdRef.markForCheck();
  }
}
