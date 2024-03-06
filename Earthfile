VERSION 0.8

deps:
    FROM alpine:3.19.1
    COPY ./charts ./charts
    COPY ./kind ./kind
    COPY ./scripts ./scripts
    SAVE ARTIFACT ./charts
    SAVE ARTIFACT ./kind
    SAVE ARTIFACT ./scripts

KIND_CREATE_LOCAL:
    FUNCTION
    RUN chmod +x ./scripts/kind_setup.sh
    RUN ./scripts/kind_setup.sh create-cluster
    RUN ./scripts/kind_setup.sh get-secrets

KIND_RECREATE_LOCAL:
    FUNCTION
    RUN kind delete cluster --name lgc
    DO +KIND_CREATE_LOCAL

kind-create-local:
    LOCALLY
    DO +KIND_CREATE_LOCAL

kind-recreate-local:
    LOCALLY
    DO +KIND_RECREATE_LOCAL