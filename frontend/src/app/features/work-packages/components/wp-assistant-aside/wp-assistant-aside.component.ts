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

import { ChangeDetectionStrategy, ChangeDetectorRef, Component, ElementRef, HostListener, Input, OnInit, inject } from '@angular/core';
import { debounceTime, distinctUntilChanged, filter, map } from 'rxjs/operators';
import { PathHelperService } from 'core-app/core/path-helper/path-helper.service';
import { WorkPackageResource } from 'core-app/features/hal/resources/work-package-resource';
import { HalEventsService } from 'core-app/features/hal/services/hal-events.service';
import { HalResourceEditingService } from 'core-app/shared/components/fields/edit/services/hal-resource-editing.service';
import { UntilDestroyedMixin } from 'core-app/shared/helpers/angular/until-destroyed.mixin';
import isNewResource from 'core-app/features/hal/helpers/is-new-resource';

const DRAFT_DEBOUNCE_MS = 600;

@Component({
  selector: 'op-wp-assistant-aside',
  template: '<turbo-frame id="assistant-wp-aside-frame" class="hide-when-print" [attr.src]="src"></turbo-frame>',
  changeDetection: ChangeDetectionStrategy.OnPush,
  standalone: false,
})
export class WorkPackageAssistantAsideComponent extends UntilDestroyedMixin implements OnInit {
  @Input() workPackage:WorkPackageResource;

  src:string|null = null;

  private readonly pathHelper = inject(PathHelperService);
  private readonly halEvents = inject(HalEventsService);
  private readonly halEditing = inject(HalResourceEditingService);
  private readonly cdRef = inject(ChangeDetectorRef);
  private readonly elementRef = inject<ElementRef<HTMLElement>>(ElementRef);

  private refreshes = 0;

  ngOnInit():void {
    if (isNewResource(this.workPackage)) {
      this.watchDraft();
    } else {
      this.watchSaves();
    }
  }

  @HostListener('click', ['$event'])
  keepDraftOpen(event:MouseEvent):void {
    const link = (event.target as HTMLElement).closest<HTMLAnchorElement>('a[href]');
    if (link && isNewResource(this.workPackage)) {
      event.preventDefault();
      window.open(link.href, '_blank', 'noopener');
    }
  }

  private watchSaves():void {
    this.halEvents.events$
      .pipe(
        this.untilDestroyed(),
        filter((event) => event.resourceType === 'WorkPackage' && event.eventType === 'updated' && event.id === this.workPackage.id),
      )
      .subscribe(() => {
        this.refreshes += 1;
        this.show(`${this.pathHelper.staticBase}/assistant/work_packages/${this.workPackage.id}/aside?refresh=${this.refreshes}&placed=${this.placedFields().join(',')}`);
      });
  }

  private placedFields():string[] {
    const view = this.elementRef.nativeElement.closest('wp-single-view') ?? document;
    return Array.from(view.querySelectorAll<HTMLElement>('op-wp-assistant-field-slot[data-assistant-field]'))
      .filter((slot) => slot.offsetParent !== null)
      .map((slot) => slot.dataset.assistantField!);
  }

  private watchDraft():void {
    this.halEditing
      .temporaryEditResource(this.workPackage)
      .values$()
      .pipe(
        this.untilDestroyed(),
        map((draft) => ({
          subject: String(draft.subject ?? ''),
          project: (draft.project as { id?:string }|undefined)?.id,
          type: (draft.type as { id?:string }|undefined)?.id,
        })),
        debounceTime(DRAFT_DEBOUNCE_MS),
        distinctUntilChanged((a, b) => a.subject === b.subject && a.project === b.project && a.type === b.type),
      )
      .subscribe(({ subject, project, type }) => {
        if (!project || !type || subject.trim().length === 0) {
          this.show(null);
          return;
        }

        const query = new URLSearchParams({ project_id: project, type_id: type, subject });
        this.show(`${this.pathHelper.staticBase}/assistant/work_packages/duplicate_aside?${query.toString()}`);
      });
  }

  private show(src:string|null):void {
    this.src = src;
    this.cdRef.markForCheck();
  }
}
