# frozen_string_literal: true
# rubocop:todo all

# Copyright (C) 2018-2020 MongoDB Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Mongo
  module Operation
    class ParallelScan

      # A MongoDB parallelscan operation sent as an op message.
      #
      # @api private
      #
      # @since 2.5.2
      class OpMsg < OpMsgBase
        include CausalConsistencySupported
        include ExecutableTransactionLabel
        include PolymorphicResult

        private

        def selector(connection, context)
          sel = { :parallelCollectionScan => coll_name, :numCursors => cursor_count }
          sel[:maxTimeMS] = max_time_ms if max_time_ms
          if read_concern
            sel[:readConcern] = Options::Mapper.transform_values_to_strings(
              read_concern)
          end
          sel
        end
      end
    end
  end
end
