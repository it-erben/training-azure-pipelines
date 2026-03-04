# Azure Pipeline Training Labs

Praxisnahe Übungsaufgaben für eine Azure DevOps Pipeline-Schulung.

## Voraussetzungen

- Azure-Subscription (wird vom Trainer bereitgestellt)
- Zugang zur gemeinsamen Azure DevOps Organisation
- Git Bash (Windows) oder Terminal (macOS/Linux)
- Azure CLI installiert (`az --version`)
- Ein Code-Editor (z.B. Visual Studio Code)

## Einrichtung

```bash
# Azure CLI installieren (falls noch nicht vorhanden)
# https://docs.microsoft.com/de-de/cli/azure/install-azure-cli

# Azure DevOps Extension installieren
az extension add --name azure-devops --yes

# Bei Azure anmelden
az login

# Subscription setzen
az account set --subscription "30b490cd-637c-4934-87a7-a38eba455adf"

# Azure DevOps Standardwerte konfigurieren (XX = Teilnehmernummer)
az devops configure --defaults \
  organization=https://dev.azure.com/iterben \
  project=teilnehmerXX
```

## Übersicht der Labs

### Grundlagen (Labs 01-05)

| Lab | Titel | Schwierigkeit | Zeitbedarf |
|-----|-------|---------------|------------|
| [Lab 01](labs/lab-01-devops-organisation/) | Azure DevOps Organisation und Projekt anlegen | Beginner | 20 Min |
| [Lab 02](labs/lab-02-erste-pipeline/) | Erste Pipeline mit YAML erstellen | Beginner | 25 Min |
| [Lab 03](labs/lab-03-trigger/) | Trigger konfigurieren (Branch, Path, Schedule) | Beginner | 25 Min |
| [Lab 04](labs/lab-04-variablen/) | Variablen und Variable Groups | Beginner | 25 Min |
| [Lab 05](labs/lab-05-keyvault-secrets/) | Secrets mit Azure Key Vault verknüpfen | Beginner | 30 Min |

### Build Pipelines (Labs 06-10)

| Lab | Titel | Schwierigkeit | Zeitbedarf |
|-----|-------|---------------|------------|
| [Lab 06](labs/lab-06-multi-stage/) | Multi-Stage Pipelines | Intermediate | 30 Min |
| [Lab 07](labs/lab-07-artefakte/) | Build-Artefakte erzeugen und publizieren | Intermediate | 25 Min |
| [Lab 08](labs/lab-08-docker-acr/) | Docker-Images bauen und in ACR pushen | Intermediate | 35 Min |
| [Lab 09](labs/lab-09-caching/) | Caching-Strategien | Intermediate | 20 Min |
| [Lab 10](labs/lab-10-matrix-builds/) | Matrix-Builds für mehrere Plattformen | Intermediate | 25 Min |

### Release und Deployment (Labs 11-15)

| Lab | Titel | Schwierigkeit | Zeitbedarf |
|-----|-------|---------------|------------|
| [Lab 11](labs/lab-11-deployment-jobs/) | Deployment Jobs und Environments | Intermediate | 30 Min |
| [Lab 12](labs/lab-12-approval-gates/) | Approval Gates und Checks | Intermediate | 25 Min |
| [Lab 13](labs/lab-13-app-service-deploy/) | Deployment nach Azure App Service | Intermediate | 35 Min |
| [Lab 14](labs/lab-14-blue-green/) | Blue/Green Deployment | Advanced | 35 Min |
| [Lab 15](labs/lab-15-rollback/) | Rollback-Strategien | Advanced | 30 Min |

### Infrastruktur als Code (Labs 16-18)

| Lab | Titel | Schwierigkeit | Zeitbedarf |
|-----|-------|---------------|------------|
| [Lab 16](labs/lab-16-terraform/) | Terraform mit Azure Pipelines | Advanced | 40 Min |
| [Lab 17](labs/lab-17-bicep/) | Bicep-Deployments | Advanced | 30 Min |
| [Lab 18](labs/lab-18-drift-detection/) | Infrastructure Drift Detection | Advanced | 30 Min |

### Fortgeschrittene Themen (Labs 19-20)

| Lab | Titel | Schwierigkeit | Zeitbedarf |
|-----|-------|---------------|------------|
| [Lab 19](labs/lab-19-self-hosted-agent/) | Self-hosted Agent auf Linux einrichten | Advanced | 35 Min |
| [Lab 20](labs/lab-20-templates/) | Pipeline-Templates und Wiederverwendung | Advanced | 35 Min |

**Gesamtzeit**: ca. 10 Stunden (bei durchschnittlichem Tempo)

## Kostenhinweise

Die Labs sind so konzipiert, dass die Azure-Kosten minimal bleiben:

- Die meisten Labs verwenden den Free Tier (F1) für App Services
- Azure Container Registry (Basic): ca. 0.17 EUR/Tag
- Key Vault: vernachlässigbare Kosten
- **Wichtig**: Lab 14 (Blue/Green) verwendet einen S1-Plan (~1.60 EUR/Tag).
  Lösche ihn nach dem Lab!

Führe nach Abschluss aller Labs das Cleanup-Script aus:

```bash
bash scripts/cleanup-all.sh
```

## Konventionen

- **Teilnehmer-Account**: Jeder Teilnehmer erhält einen Account
  `teilnehmerXX@infoiterben.onmicrosoft.com` (XX = Nummer, z.B. `01`).
- **Organisation**: Die Azure DevOps Organisation heißt `iterben`
  (`https://dev.azure.com/iterben`).
- **Projekt**: Jeder Teilnehmer hat ein eigenes Projekt namens `teilnehmerXX`.
- **Resource Group**: Alle Azure-Ressourcen werden in `rg-pipeline-training`
  erstellt (sofern nicht anders angegeben).
- **Region**: Alle Ressourcen werden in `West Europe` (westeurope) erstellt.

## Troubleshooting

### Häufige Probleme

1. **"No hosted parallelism has been purchased or granted"**
   Für neue Azure DevOps Organisationen muss Parallelismus beantragt werden.
   Der Trainer kümmert sich darum.

2. **Azure CLI nicht authentifiziert**

   ```bash
   az login
   az account set --subscription "30b490cd-637c-4934-87a7-a38eba455adf"
   ```

3. **Git-Authentifizierung fehlgeschlagen**
   Stelle sicher, dass der Git Credential Manager aktiv ist
   (`git config --global credential.helper` sollte `manager` ausgeben).
   Siehe Lab 01, Schritt 4.

4. **YAML-Syntaxfehler**
   Achte auf korrekte Einrückung (2 Spaces, keine Tabs). Verwende den YAML-Editor in Azure DevOps zur Validierung.
