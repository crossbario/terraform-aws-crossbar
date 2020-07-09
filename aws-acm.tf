# Copyright (c) Crossbar.io Technologies GmbH. Licensed under GPL 3.0.

# TLS certificate for domain, managed (auto-refreshed) by AWS
resource "aws_acm_certificate" "crossbar_dns_cert" {
    # only instantiate the resource when TLS is enabled

    # verify certificate using DNS records created in Route 53
    validation_method = "DNS"

    # the certs CN:
    domain_name       = var.dns-domain-name

    # the certs SANs:
    #
    # IMPORTANT: only use 1 SAN currently, as there is an open issue when using _multipe_ SANs:
    # https://github.com/terraform-providers/terraform-provider-aws/issues/8531
    subject_alternative_names = [
        "www.${var.dns-domain-name}",
        "data.${var.dns-domain-name}",
        "master.${var.dns-domain-name}"
    ]
}

# verification record for cert CN
resource "aws_route53_record" "crossbar_dns_cert_validation_cn_rec" {
    # only instantiate the resource when TLS is enabled

    name    = aws_acm_certificate.crossbar_dns_cert.domain_validation_options.0.resource_record_name
    type    = aws_acm_certificate.crossbar_dns_cert.domain_validation_options.0.resource_record_type
    zone_id = aws_route53_zone.crossbar-zone.zone_id
    records = [
        aws_acm_certificate.crossbar_dns_cert.domain_validation_options.0.resource_record_value
    ]
    ttl     = 60
}

# verification record for cert SAN[0]
resource "aws_route53_record" "crossbar_dns_cert_validation_alt1_rec" {
    # only instantiate the resource when TLS is enabled

    name    = aws_acm_certificate.crossbar_dns_cert.domain_validation_options.1.resource_record_name
    type    = aws_acm_certificate.crossbar_dns_cert.domain_validation_options.1.resource_record_type
    zone_id = aws_route53_zone.crossbar-zone.zone_id
    records = [
        aws_acm_certificate.crossbar_dns_cert.domain_validation_options.1.resource_record_value
    ]
    ttl     = 60
}

# verification record for cert SAN[1]
resource "aws_route53_record" "crossbar_dns_cert_validation_alt2_rec" {
    # only instantiate the resource when TLS is enabled

    name    = aws_acm_certificate.crossbar_dns_cert.domain_validation_options.2.resource_record_name
    type    = aws_acm_certificate.crossbar_dns_cert.domain_validation_options.2.resource_record_type
    zone_id = aws_route53_zone.crossbar-zone.zone_id
    records = [
        aws_acm_certificate.crossbar_dns_cert.domain_validation_options.2.resource_record_value
    ]
    ttl     = 60
}

# verification record for cert SAN[2]
resource "aws_route53_record" "crossbar_dns_cert_validation_alt3_rec" {
    # only instantiate the resource when TLS is enabled

    name    = aws_acm_certificate.crossbar_dns_cert.domain_validation_options.3.resource_record_name
    type    = aws_acm_certificate.crossbar_dns_cert.domain_validation_options.3.resource_record_type
    zone_id = aws_route53_zone.crossbar-zone.zone_id
    records = [
        aws_acm_certificate.crossbar_dns_cert.domain_validation_options.3.resource_record_value
    ]
    ttl     = 60
}

# certificate verification record
resource "aws_acm_certificate_validation" "crossbar_dns_cert_validation" {
    # only instantiate the resource when TLS is enabled

    certificate_arn = aws_acm_certificate.crossbar_dns_cert.arn
    validation_record_fqdns = [
        aws_route53_record.crossbar_dns_cert_validation_cn_rec.fqdn,
        aws_route53_record.crossbar_dns_cert_validation_alt1_rec.fqdn
    ]
}
