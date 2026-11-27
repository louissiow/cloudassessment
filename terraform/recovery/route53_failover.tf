# CloudFront (t1dx-cf-edge) uses api-origin.t1dx.example as its API origin.
# CloudFront origin groups only fail over GET/HEAD/OPTIONS, so they can't protect POST /transfers.
# Region failover therefore happens in DNS, behind CloudFront, driven by ARC routing controls.

resource "aws_route53_record" "api_origin" {
  for_each = {
    apse5 = "PRIMARY"
    apse1 = "SECONDARY"
  }

  zone_id         = var.public_zone_id
  name            = var.origin_record_name
  type            = "A"
  set_identifier  = "t1dx-api-${each.key}"
  health_check_id = aws_route53_health_check.routing_control[each.key].id

  failover_routing_policy {
    type = each.value
  }

  alias {
    name                   = var.apigw_regional_domain[each.key].domain_name
    zone_id                = var.apigw_regional_domain[each.key].zone_id
    evaluate_target_health = false # routing control is the single source of truth for Region choice
  }
}
