extension radius

@description('The Radius Environment ID. Typically set by the rad CLI.')
param environment string

@description('Administrator password for the PostgreSQL database used by Spring PetClinic.')
@secure()
param postgresPassword string

@description('Username for the OCI registry the containerImages recipe pushes to (the GitHub actor for ghcr.io).')
@secure()
param registryUsername string

@description('Password/token for the OCI registry the containerImages recipe pushes to (a GitHub token with write:packages for ghcr.io).')
@secure()
param registryPassword string

resource springPetclinicApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'spring-petclinic'
  properties: {
    environment: environment
  }
}

resource postgresDb 'Radius.Data/postgreSqlDatabases@2025-08-01-preview' = {
  name: 'postgres'
  properties: {
    environment: environment
    application: springPetclinicApp.id
    codeReference: 'src/main/resources/application-postgres.properties#L3'
    database: 'petclinic'
    username: 'myadmin'
    password: postgresPassword
  }
}

// Registry push credentials for the containerImages recipe. The name must match
// the recipe pack's containerImagesRegistrySecretName.
resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: springPetclinicApp.id
    data: {
      username: {
        value: registryUsername
      }
      password: {
        value: registryPassword
      }
    }
  }
}

resource springPetclinicImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'spring-petclinic-image'
  properties: {
    environment: environment
    application: springPetclinicApp.id
    codeReference: 'Dockerfile'
    build: {
      source: 'git::https://github.com/Reshrahim/spring-petclinic.git?ref=b46c8d038649fddb747315af453f29a3eb0cff97'
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource springPetclinicContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'spring-petclinic'
  properties: {
    environment: environment
    application: springPetclinicApp.id
    codeReference: 'src/main/java/org/springframework/samples/petclinic/PetClinicApplication.java'
    containers: {
      petclinic: {
        image: springPetclinicImage.properties.imageReference
        ports: {
          web: {
            containerPort: 8080
          }
        }
        env: {
          SPRING_PROFILES_ACTIVE: {
            value: 'postgres'
          }
          POSTGRES_URL: {
            // Port is fixed at 5432 for Azure Database for PostgreSQL Flexible
            // Server; the recipe does not publish a port output on the resource.
            value: 'jdbc:postgresql://${postgresDb.properties.host}:5432/petclinic'
          }
          POSTGRES_USER: {
            value: 'myadmin'
          }
          POSTGRES_PASS: {
            value: postgresPassword
          }
        }
      }
    }
    connections: {
      postgresdb: {
        source: postgresDb.id
      }
    }
  }
}

// External ingress is intentionally not modeled here.
//
// The environment's Kubernetes routes recipe provisions Gateway API resources
// (gateway.networking.k8s.io/HTTPRoute) and attaches them to a pre-existing
// Gateway named by the recipe's `gatewayName` parameter. The target AKS cluster
// has no Gateway API CRDs installed, and the deploy workflow supplies an empty
// `gatewayName`, so a Radius.Compute/routes resource cannot be provisioned here.
//
// The container still publishes port 8080 as a cluster-internal service. To add
// external ingress, install the Gateway API CRDs plus a Gateway on the cluster,
// point the environment at it, and then re-add a Radius.Compute/routes resource
// targeting container `petclinic` on port 8080.
