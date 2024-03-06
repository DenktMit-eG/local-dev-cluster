VERSION 0.8
FROM alpine:3.19.1

deps:
    COPY ./charts ./charts
    COPY ./kind ./kind
    SAVE ARTIFACT ./charts
    SAVE ARTIFACT ./kind

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