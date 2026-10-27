# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

module Assistant
  module Cable
    # The cable connection for the whole application: it is the same signed-in
    # browser session the pages use, so a socket is only ever opened by
    # someone who could load the page that names the stream.
    class Connection < ActionCable::Connection::Base
      include ::OpenProject::Authentication::SessionExpiration

      identified_by :current_user

      def connect
        self.current_user = session_user || reject_unauthorized_connection
      end

      private

      def session_user
        return if session.blank? || session_ttl_expired?

        User.active.find_by(id: session["user_id"])&.then { it.logged? ? it : nil }
      end

      def session = request.session
    end
  end
end
