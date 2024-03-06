VERSION 0.8
FROM alpine:3.19.1

deps:
    COPY ./charts ./charts
    COPY ./kind ./kind
    COPY ./scripts ./scripts
    SAVE ARTIFACT ./charts
    SAVE ARTIFACT ./kind
    SAVE ARTIFACT ./scripts

kind-create-local:
    LOCALLY
    RUN chmod +x ./scripts/kind_setup.sh
    RUN ./scripts/kind_setup.sh create-cluster
    RUN ./scripts/kind_setup.sh get-secrets

kind-recreate-local:
    LOCALLY
    RUN kind delete cluster --name lgc
    # create cluster
    RUN chmod +x ./scripts/kind_setup.sh
    RUN ./scripts/kind_setup.sh create-cluster
    RUN ./scripts/kind_setup.sh get-secrets