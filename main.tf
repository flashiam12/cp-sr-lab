terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
    helm = {
      source = "hashicorp/helm"
      version = "2.9.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "docker-desktop"
  }
}

provider "kubernetes" {
  alias = "kubernetes-raw"
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}

provider "kubectl" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}


data "kubectl_filename_list" "cfk-crds" {
    pattern = "${path.module}/dependencies/confluent-for-kubernetes/crds/*.yaml"
}

resource "kubectl_manifest" "cfk-crds" {
  count     = length(data.kubectl_filename_list.cfk-crds.matches)
  yaml_body = file(element(data.kubectl_filename_list.cfk-crds.matches, count.index))
}

resource "helm_release" "confluent-operator" {
  name       = "confluent-operator"
  chart      = "${path.module}/dependencies/confluent-for-kubernetes"
  namespace = "confluent"
  cleanup_on_fail = true
  create_namespace = true
  values = [file("${path.module}/dependencies/confluent-for-kubernetes/values.yaml")]
  depends_on = [
    kubectl_manifest.cfk-crds
  ]
}

resource "helm_release" "ldap" {
  name = "ldap"
  chart = "${path.module}/dependencies/openldap"
  namespace = "confluent"
  cleanup_on_fail = true
  create_namespace = false
  values = [file("${path.module}/dependencies/openldap/ldaps-rbac.yaml")]
  depends_on = [ helm_release.confluent-operator ]
}

data "kubectl_file_documents" "cfk-permissions" {
    content = file("${path.module}/dependencies/confluent-for-kubernetes/cfk-permission.yaml")
}

resource "kubectl_manifest" "cfk-permissions" {
  for_each  = data.kubectl_file_documents.cfk-permissions.manifests
  yaml_body = each.value
  depends_on = [
    helm_release.confluent-operator
  ]
}

resource "kubernetes_namespace" "kafka" {
  provider = kubernetes.kubernetes-raw
  metadata {
    annotations = {
      name = "strimizi-kafka"
    }

    name = "kafka"
  }
}

resource "kubernetes_namespace" "zookeeper" {
  provider = kubernetes.kubernetes-raw
  metadata {
    annotations = {
      name = "strimizi-kafka"
    }

    name = "zookeeper"
  }
}

resource "kubernetes_namespace" "srops" {
  provider = kubernetes.kubernetes-raw
  metadata {
    annotations = {
      name = "strimizi-kafka"
    }

    name = "srops"
  }
}

data "kubectl_file_documents" "strimzi-operator" {
    content = file("${path.module}/strimzi-operator.yaml")
}

resource "kubectl_manifest" "strimzi-operator" {
  for_each  = data.kubectl_file_documents.strimzi-operator.manifests
  yaml_body = each.value
  depends_on = [
    helm_release.confluent-operator,
    kubernetes_namespace.kafka
  ]
}

data "kubectl_file_documents" "strimzi-operator-no-gates" {
    content = file("${path.module}/strimzi-operator-no-feature-gate.yaml")
}

resource "kubectl_manifest" "strimzi-operator-no-gates" {
  for_each  = data.kubectl_file_documents.strimzi-operator-no-gates.manifests
  yaml_body = each.value
  depends_on = [
    helm_release.confluent-operator,
    kubernetes_namespace.zookeeper
  ]
}

data "kubectl_file_documents" "strimzi-operator-sr-ops" {
    content = file("${path.module}/strimzi-operator-sr-ops.yaml")
}

resource "kubectl_manifest" "strimzi-operator-sr-ops" {
  for_each  = data.kubectl_file_documents.strimzi-operator-sr-ops.manifests
  yaml_body = each.value
  depends_on = [
    helm_release.confluent-operator,
    kubernetes_namespace.srops
  ]
}

# data "kubectl_file_documents" "osk-kraft" {
#     content = file("${path.module}/osk-kraft.yaml")
# }

# resource "kubectl_manifest" "osk-kraft" {
#   for_each  = data.kubectl_file_documents.osk-kraft.manifests
#   yaml_body = each.value
#   depends_on = [
#     kubectl_manifest.strimzi-operator
#   ]
# }

data "kubectl_file_documents" "osk-non-kraft" {
    content = file("${path.module}/osk-non-kraft.yaml")
}

resource "kubectl_manifest" "osk-non-kraft" {
  for_each  = data.kubectl_file_documents.osk-non-kraft.manifests
  yaml_body = each.value
  depends_on = [
    kubectl_manifest.strimzi-operator-no-gates
  ]
}

# data "kubectl_file_documents" "osk-non-kraft-sr-ops" {
#     content = file("${path.module}/osk-non-kraft-sr-ops.yaml")
# }

# resource "kubectl_manifest" "osk-non-kraft-sr-ops" {
#   for_each  = data.kubectl_file_documents.osk-non-kraft-sr-ops.manifests
#   yaml_body = each.value
#   depends_on = [
#     kubectl_manifest.strimzi-operator-sr-ops
#   ]
# }

data "kubectl_file_documents" "cp-server-ops-non-kraft" {
    content = file("${path.module}/cp-server-ops-non-kraft.yaml")
}

resource "kubectl_manifest" "cp-server-ops-non-kraft" {
  for_each  = data.kubectl_file_documents.cp-server-ops-non-kraft.manifests
  yaml_body = each.value
  depends_on = [
    helm_release.confluent-operator
  ]
}

data "kubectl_file_documents" "cp-sr-cp-non-kraft" {
    content = file("${path.module}/cp-sr-cp-non-kraft.yaml")
}

resource "kubectl_manifest" "cp-sr-cp-non-kraft" {
  for_each  = data.kubectl_file_documents.cp-sr-cp-non-kraft.manifests
  yaml_body = each.value
  depends_on = [
    kubectl_manifest.cp-server-ops-non-kraft
  ]
}


data "kubectl_file_documents" "osk-topic" {
    content = file("${path.module}/osk-topic.yaml")
}

resource "kubectl_manifest" "osk-topic" {
  for_each  = data.kubectl_file_documents.osk-topic.manifests
  yaml_body = each.value
  depends_on = [
    # kubectl_manifest.osk-kraft
  ]
}

# data "kubectl_file_documents" "osk-user" {
#     content = file("${path.module}/osk-user.yaml")
# }

# resource "kubectl_manifest" "osk-user" {
#   for_each  = data.kubectl_file_documents.osk-user.manifests
#   yaml_body = each.value
#   depends_on = [
#     kubectl_manifest.osk-kraft
#   ]
# }

data "kubectl_file_documents" "ubuntu-lab" {
    content = file("${path.module}/ubuntu-lab.yaml")
}

resource "kubectl_manifest" "ubuntu-lab" {
  for_each  = data.kubectl_file_documents.ubuntu-lab.manifests
  yaml_body = each.value
  depends_on = [
    helm_release.confluent-operator,
    kubectl_manifest.strimzi-operator
  ]
}

data "kubectl_file_documents" "ubuntu-tls-lab" {
    content = file("${path.module}/ubuntu-tls-lab.yaml")
}

resource "kubectl_manifest" "ubuntu-tls-lab" {
  for_each  = data.kubectl_file_documents.ubuntu-tls-lab.manifests
  yaml_body = each.value
  depends_on = [
    helm_release.confluent-operator,
    kubectl_manifest.strimzi-operator
  ]
}

# data "kubectl_file_documents" "cp-sr" {
#     content = file("${path.module}/cp-sr.yaml")
# }

# resource "kubectl_manifest" "cp-sr" {
#   for_each  = data.kubectl_file_documents.cp-sr.manifests
#   yaml_body = each.value
#   depends_on = [
#     helm_release.confluent-operator
#   ]
# }

# data "kubectl_file_documents" "cp-sr-non-kraft" {
#     content = file("${path.module}/cp-sr-non-kraft.yaml")
# }

# resource "kubectl_manifest" "cp-sr-non-kraft" {
#   for_each  = data.kubectl_file_documents.cp-sr-non-kraft.manifests
#   yaml_body = each.value
#   depends_on = [
#     helm_release.confluent-operator
#   ]
# }

resource "kubernetes_secret" "rest-credential" {
  provider = kubernetes.kubernetes-raw
  metadata {
    name = "basicwithrolesr"
    namespace = "confluent"
  }

  data = {
    "basic.txt" = "${file("./cp-sr-users.txt")}"
  }

  type = "kubernetes.io/generic"
}

resource "kubernetes_secret" "restclass-rest-credential" {
  provider = kubernetes.kubernetes-raw
  metadata {
    name = "rest-credential"
    namespace = "confluent"
  }

  data = {
    "bearer.txt" = "${file("./secrets/cp-creds/bearer.txt")}"
    "basic.txt" = "${file("./secrets/cp-creds/bearer.txt")}"
  }

  type = "kubernetes.io/generic"
}

resource "kubernetes_secret" "ca-pair-sslcerts" {
  provider = kubernetes.kubernetes-raw
  metadata {
    name = "ca-pair-sslcerts"
    namespace = "confluent"
  }

  data = {
    "tls.crt" = "${file("./secrets/cp-certs/ca.pem")}"
    "tls.key" = "${file("./secrets/cp-certs/ca-key.pem")}"
  }

  type = "kubernetes.io/tls"
}

resource "kubernetes_secret" "mds-token" {
  provider = kubernetes.kubernetes-raw
  metadata {
    name = "mds-token"
    namespace = "confluent"
  }

  data = {
    "mdsPublicKey.pem" = "${file("./secrets/mds-certs/mds-publickey.txt")}"
    "mdsTokenKeyPair.pem" = "${file("./secrets/mds-certs/mds-tokenkeypair.txt")}"
  }

  type = "kubernetes.io/generic"
}

resource "kubernetes_secret" "credential" {
  provider = kubernetes.kubernetes-raw
  metadata {
    name = "credential"
    namespace = "confluent"
  }

  data = {
    "plain-users.json" = "${file("./secrets/cp-creds/kafka-sasl-users.json")}"
    "plain.txt" = "${file("./secrets/cp-creds/client-kafka-sasl-user.txt")}"
    "digest-users.json" = "${file("./secrets/cp-creds/zookeeper-sasl-digest-users.json")}"
    "digest.txt" = "${file("./secrets/cp-creds/kafka-zookeeper-credentials.txt")}"
    "ldap.txt" = "${file("./secrets/cp-creds/ldap.txt")}"
  }

  type = "kubernetes.io/generic"
}

resource "kubernetes_secret" "sr-mds-client" {
  provider = kubernetes.kubernetes-raw
  metadata {
    name = "sr-mds-client"
    namespace = "confluent"
  }

  data = {
    "bearer.txt" = "${file("./secrets/sr-mds-client.txt")}"
  }

  type = "kubernetes.io/generic"
}

resource "kubernetes_secret" "mds-client" {
  provider = kubernetes.kubernetes-raw
  metadata {
    name = "mds-client"
    namespace = "confluent"
  }

  data = {
    "bearer.txt" = "${file("./secrets/kafka-mds-client.txt")}"
  }

  type = "kubernetes.io/generic"
}


