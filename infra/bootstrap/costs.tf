# Budget mensual + Cost Anomaly Detection (doc 02).

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-mensual"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Mientras haya créditos, el costo neto es 0 y un budget con créditos
  # incluidos nunca alertaría. Se mide el uso bruto para enterarse a tiempo.
  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# Cost Explorer tarda hasta 24 h en activarse en una cuenta nueva y, mientras
# tanto, la API rechaza todo: usar enable_anomaly_detection = false.
#
# AWS permite un solo monitor DIMENSIONAL/SERVICE por cuenta y al activar
# Cost Explorer suele crear uno por defecto. En ese caso usar
# create_anomaly_monitor = false + existing_anomaly_monitor_arn.
resource "aws_ce_anomaly_monitor" "services" {
  count = var.enable_anomaly_detection && var.create_anomaly_monitor ? 1 : 0

  name              = "${var.project}-servicios"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "email" {
  count = var.enable_anomaly_detection ? 1 : 0

  name             = "${var.project}-anomalias"
  frequency        = "DAILY"
  monitor_arn_list = [var.create_anomaly_monitor ? aws_ce_anomaly_monitor.services[0].arn : var.existing_anomaly_monitor_arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }

  lifecycle {
    precondition {
      condition     = var.create_anomaly_monitor || var.existing_anomaly_monitor_arn != null
      error_message = "Si create_anomaly_monitor = false hay que pasar existing_anomaly_monitor_arn."
    }
  }
}
