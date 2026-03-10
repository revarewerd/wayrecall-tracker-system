#!/bin/bash
# Скрипт коммита всех submodule-ов и основного репо
set -e

ROOT="/Users/wogul/vsCodeProjects/wayrecall-tracker"

commit_service() {
    local dir="$1"
    local msg="$2"
    echo "=== Committing $dir ==="
    cd "$ROOT/services/$dir"
    git add -A
    git diff --cached --quiet && echo "  (nothing to commit)" && return 0
    git commit -m "$msg"
    echo "  OK"
}

# 1. History Writer
commit_service "history-writer" "refactor(hw): telemetry->gps, CM format alignment, 224 tests pass"

# 2. Connection Manager  
commit_service "connection-manager" "fix(cm): GpsPoint fixes, WialonBinaryParser, new tests"

# 3. Web Frontend
commit_service "web-frontend" "feat(web): Dockerfile, MapView, API client, hooks, pages"

# 4. WebSocket Service
commit_service "websocket-service" "fix(ws): domain entities, MessageRouter, tests update"

# 5. Admin Service
commit_service "admin-service" "fix(admin): service layer fixes, add tests"

# 6. Analytics Service
commit_service "analytics-service" "fix(analytics): TripDetector, ExportService, report generators, add tests"

# 7. API Gateway
commit_service "api-gateway" "fix(gateway): config, Main, AuthMiddleware, ApiRouter, HealthService, add tests"

# 8. Integration Service
commit_service "integration-service" "fix(integration): ApiKeyValidator, WebhookSender, WialonSender, add tests"

# 9. Maintenance Service
commit_service "maintenance-service" "fix(maintenance): MaintenanceService fixes, add tests"

# 10. Notification Service
commit_service "notification-service" "fix(notifications): DeliveryService, RuleMatcher, TemplateEngine, ThrottleService, add tests"

# 11. Rule Checker
commit_service "rule-checker" "fix(rc): GeozoneChecker, SpeedChecker fixes, add tests"

# 12. Sensors Service
commit_service "sensors-service" "fix(sensors): SensorProcessor, SensorsService fixes, add tests"

# 13. User Service
commit_service "user-service" "fix(users): AuditService, CompanyService, GroupService, PermissionService, RoleService, UserService fixes, add tests"

# 14. Billing Service
commit_service "billing-service" "feat(billing): add docs, payment tests"

# 15. Device Manager
commit_service "device-manager" "feat(dm): add tests for api, consumer, infrastructure, repository"

# 16. Ticket Service
commit_service "ticket-service" "feat(ticket): add docs, config and repository tests"

# 17. Web Billing
commit_service "web-billing" "chore(web-billing): add nginx-prod.conf"

echo ""
echo "=== All submodules committed ==="

# Main repo
echo "=== Committing main repo ==="
cd "$ROOT"
git add -A
git commit -m "chore: update submodules, docs, infra, copilot-instructions

- copilot-instructions: AI comment convention system (TODO/FIXME/QUESTION/NOTE/REVIEW tags)
- build.sbt updates
- docs: ARCHITECTURE_BLOCK3, STELS_GAP_ANALYSIS, kafka TOPICS
- test-stand: docker-compose split, prometheus, security, test data
- daily tasks and ai chat history
- learning materials"
echo "=== Main repo committed ==="

echo ""
echo "=== ALL COMMITS DONE ==="
