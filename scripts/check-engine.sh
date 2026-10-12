#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc Shared/CalendarEngine.swift Tests/CalendarEngineTests.swift -o /tmp/uniflow-widget-calendar-tests
/tmp/uniflow-widget-calendar-tests
