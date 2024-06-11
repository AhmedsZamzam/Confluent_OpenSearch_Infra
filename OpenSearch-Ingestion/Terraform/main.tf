resource "random_id" "env_display_id" {
    byte_length = 4
}

# ------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------

resource "confluent_environment" "staging" {
  display_name = "${var.prefix}-environment-${random_id.env_display_id.hex}"
}



# ------------------------------------------------------
# KAFKA Cluster, Attachement and Connection
# ------------------------------------------------------

resource "confluent_kafka_cluster" "cluster" {
  display_name = "${var.prefix}-cluster-${random_id.env_display_id.hex}"
  availability = "MULTI_ZONE"
  cloud        = "AWS"
  region       = var.region
  enterprise {}
  environment {
    id = confluent_environment.staging.id
  }
}

resource "confluent_private_link_attachment" "pla" {
  cloud = "AWS"
  region = var.region
  display_name = "${var.prefix}-staging-aws-platt"
  environment {
    id = confluent_environment.staging.id
  }
}

resource "confluent_private_link_attachment_connection" "plac" {
  display_name = "staging-aws-plattc"
  environment {
    id = confluent_environment.staging.id
  }
  aws {
    vpc_endpoint_id = aws_vpc_endpoint.privatelink.id
  }

  private_link_attachment {
    id = confluent_private_link_attachment.pla.id
  }
}

# ------------------------------------------------------
# SERVICE ACCOUNTS
# ------------------------------------------------------

resource "confluent_service_account" "app-manager" {
  display_name = "app-manager"
  description  = "Service account to manage 'inventory' Kafka cluster"
}

# ------------------------------------------------------
# ROLE BINDINGS
# ------------------------------------------------------

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.cluster.rbac_crn
}

# ------------------------------------------------------
# API KEYS
# ------------------------------------------------------

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.cluster.id
    api_version = confluent_kafka_cluster.cluster.api_version
    kind        = confluent_kafka_cluster.cluster.kind

    environment {
      id = confluent_environment.staging.id
    }
  }

  # The goal is to ensure that confluent_role_binding.app-manager-kafka-cluster-admin is created before
  # confluent_api_key.app-manager-kafka-api-key is used to create instances of
  # confluent_kafka_topic, confluent_kafka_acl resources.

  # 'depends_on' meta-argument is specified in confluent_api_key.app-manager-kafka-api-key to avoid having
  # multiple copies of this definition in the configuration which would happen if we specify it in
  # confluent_kafka_topic, confluent_kafka_acl resources instead.
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin,
    confluent_private_link_attachment_connection.plac
  ]
}

