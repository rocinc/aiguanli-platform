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

import { NO_ERRORS_SCHEMA } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { of } from 'rxjs';
import { ApiV3Service } from 'core-app/core/apiv3/api-v3.service';
import { DeviceService } from 'core-app/core/browser/device.service';
import { TimezoneService } from 'core-app/core/datetime/timezone.service';
import { I18nService } from 'core-app/core/i18n/i18n.service';
import { UrlParamsService } from 'core-app/core/navigation/url-params.service';
import { PathHelperService } from 'core-app/core/path-helper/path-helper.service';
import { INotification } from 'core-app/core/state/in-app-notifications/in-app-notification.model';
import { IanCenterService } from 'core-app/features/in-app-notifications/center/state/ian-center.service';
import { InAppNotificationEntryComponent } from './in-app-notification-entry.component';

describe('InAppNotificationEntryComponent', () => {
  let fixture:ComponentFixture<InAppNotificationEntryComponent>;
  let workPackageLookup:ReturnType<typeof vi.fn>;

  function render(notification:INotification) {
    fixture = TestBed.createComponent(InAppNotificationEntryComponent);
    fixture.componentInstance.notification = notification;
    fixture.componentInstance.aggregatedNotifications = [notification];
    fixture.detectChanges();
    return fixture.nativeElement as HTMLElement;
  }

  beforeEach(() => {
    workPackageLookup = vi.fn();
    TestBed.configureTestingModule({
      declarations: [InAppNotificationEntryComponent],
      schemas: [NO_ERRORS_SCHEMA],
      providers: [
        { provide: ApiV3Service, useValue: { work_packages: { id: workPackageLookup } } },
        { provide: I18nService, useValue: { t: (key:string) => (key.endsWith('.assistant') ? 'AI 助理' : key) } },
        { provide: IanCenterService, useValue: { query: { selectLoading: () => of(false) }, markAsRead: vi.fn() } },
        { provide: TimezoneService, useValue: {} },
        { provide: PathHelperService, useValue: { projectPath: (id:string) => `/projects/${id}` } },
        { provide: DeviceService, useValue: { isMobile: false } },
        { provide: UrlParamsService, useValue: {} },
      ],
    });
  });

  it('shows an assistant notice on a project instead of waiting for a work package', () => {
    const element = render({
      id: 14,
      reason: 'assistant',
      readIAN: false,
      _links: {
        resource: { href: '/api/v3/projects/8', title: '智能写作平台' },
        project: { href: '/api/v3/projects/8', title: '智能写作平台' },
      },
    } as unknown as INotification);

    expect(workPackageLookup).not.toHaveBeenCalled();
    expect(element.querySelector('.op-ian-item--loading')).toBeNull();
    expect(element.querySelector('op-in-app-notification-assistant')).not.toBeNull();

    const projectLink = element.querySelector<HTMLAnchorElement>('.op-ian-item--project-link');
    expect(projectLink?.textContent).toBe('智能写作平台');
    expect(projectLink?.getAttribute('href')).toBe('/projects/8');
    expect(element.querySelector('.op-ian-item--reason')?.textContent).toBe('AI 助理');
  });

  it('still waits for the work package of any other notice', () => {
    workPackageLookup.mockReturnValue({ requireAndStream: () => of() });

    const element = render({
      id: 15,
      reason: 'mentioned',
      readIAN: false,
      _links: { resource: { href: '/api/v3/work_packages/42', title: 'A work package' } },
    } as unknown as INotification);

    expect(workPackageLookup).toHaveBeenCalledWith('42');
    expect(element.querySelector('op-in-app-notification-assistant')).toBeNull();
  });
});
