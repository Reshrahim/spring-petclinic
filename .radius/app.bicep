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
            value: 'jdbc:postgresql://${postgresDb.properties.host}:${postgresDb.properties.port}/petclinic'
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

resource springPetclinicRoute 'Radius.Compute/routes@2025-08-01-preview' = {
  name: 'spring-petclinic-route'
  properties: {
    environment: environment
    application: springPetclinicApp.id
    kind: 'HTTP'
    rules: [
      {
        matches: [
          {
            httpPath: '/'
          }
        ]
        destinationContainer: {
          resourceId: springPetclinicContainer.id
          containerName: 'petclinic'
          containerPort: 8080
        }
      }
    ]
  }
}
