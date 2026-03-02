# Lab 05: Secrets mit Azure Key Vault verknüpfen

## Hintergrund

Sensible Daten wie Passwörter, API-Keys oder Connection Strings gehören
**niemals** direkt in den Quellcode oder in unverschlüsselte Pipeline-Variablen.
Azure Key Vault ist ein verwalteter Dienst zur sicheren Speicherung von Secrets,
Keys und Zertifikaten.

Azure Pipelines kann über eine **Variable Group mit Key Vault-Verknüpfung**
Secrets zur Laufzeit aus dem Vault laden. Die Secrets werden dabei nie im
Klartext in Logs angezeigt. Azure Pipelines maskiert sie automatisch.

## Voraussetzungen

Folgende Ressourcen wurden vom Trainer bereits per Terraform bereitgestellt:

- **Azure Key Vault** `kv-training-teilnehmerNN` mit drei Secrets:
  - `database-password`
  - `api-key`
  - `connection-string`
- **Service Principal** `sp-training-teilnehmerNN` mit Contributor-Rolle auf
  `rg-pipeline-training` und Leserechten (Get, List) auf dem Key Vault

Die Zugangsdaten des Service Principals (App-ID, Client Secret, Tenant-ID)
erhältst du vom Trainer.

## Aufgabenstellung

### Schritt 1: Key Vault und Secrets prüfen

Dein Key Vault ist bereits angelegt. Setze zuerst den Namen als Variable und
prüfe, ob alles vorhanden ist:

**Bash:**

```bash
# Setze den Key-Vault-Namen (NN = deine Teilnehmernummer, z.B. 01)
KV_NAME="kv-training-teilnehmerNN"
```

**PowerShell:**

```powershell
# Setze den Key-Vault-Namen (NN = deine Teilnehmernummer, z.B. 01)
$KV_NAME = "kv-training-teilnehmerNN"
```

```bash
# Prüfe, ob der Key Vault existiert und erreichbar ist.
az keyvault show --name $KV_NAME --output table

# Zeige alle Secrets im Vault an. Dieser Befehl listet nur die Namen auf,
# nicht die Werte - die bleiben geschützt.
az keyvault secret list --vault-name $KV_NAME --output table
```

Du solltest drei Secrets sehen: `database-password`, `api-key` und
`connection-string`.

### Schritt 2: Service Connection einrichten

Azure DevOps und Azure Key Vault sind zwei getrennte Dienste. Damit eine
Pipeline zur Laufzeit Secrets aus dem Key Vault lesen kann, braucht sie eine
authentifizierte Verbindung zu Azure. Diese wird über eine **Service
Connection** hergestellt, die einen **Service Principal** (eine Art technischer
Benutzer) in Azure Active Directory nutzt.

Der Service Principal wurde vom Trainer bereits erstellt. Du musst nur noch
die Service Connection in Azure DevOps anlegen. Wir machen das per CLI, da die
Azure DevOps Web-Oberfläche nur noch "App registration (automatic)" mit
**Workload Identity Federation** anbietet. Dieses neuere Auth-Schema wird von
der Key-Vault-Integration in Variable Groups jedoch nicht unterstützt.

> [!NOTE]
> **Hinweis zum Authentifizierungsmodell (Stand: 27. Februar 2026):**
> Die Verknüpfung von Key Vault in **Variable Groups** funktioniert in der
> Praxis nicht in allen Umgebungen zuverlässig mit WIF/RBAC. Es kann bei der
> Autorisierung in Azure DevOps zu einem internen Fehler kommen.
>
> Deshalb nutzt dieses Lab bewusst den kompatiblen Trainingspfad:
> **Service Principal (Client Secret) + Access Policy**.

Setze zuerst die Zugangsdaten, die du vom Trainer erhalten hast:

**Bash:**

```bash
# Zugangsdaten des Service Principals (vom Trainer erhalten)
SP_APP_ID="<App-ID vom Trainer>"
SP_PASSWORD="<Client Secret vom Trainer>"
SP_TENANT="<Tenant-ID vom Trainer>"
```

**PowerShell:**

```powershell
# Zugangsdaten des Service Principals (vom Trainer erhalten)
$SP_APP_ID = "<App-ID vom Trainer>"
$SP_PASSWORD = "<Client Secret vom Trainer>"
$SP_TENANT = "<Tenant-ID vom Trainer>"
```

Erstelle nun die Service Connection in Azure DevOps. Das Client Secret wird
über eine Umgebungsvariable übergeben:

**Bash:**

```bash
# Service Connection erstellen. Das Secret wird per Umgebungsvariable
# übergeben, damit es nicht in der Shell-Historie landet.
export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY="$SP_PASSWORD"

az devops service-endpoint azurerm create \
  --name "azure-training-connection" \
  --azure-rm-service-principal-id "$SP_APP_ID" \
  --azure-rm-subscription-id "30b490cd-637c-4934-87a7-a38eba455adf" \
  --azure-rm-subscription-name "GFU-2026-01" \
  --azure-rm-tenant-id "$SP_TENANT" \
  --output table
```

**PowerShell:**

```powershell
# Service Connection erstellen. Das Secret wird per Umgebungsvariable
# übergeben, damit es nicht in der Shell-Historie landet.
$env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = "$SP_PASSWORD"

az devops service-endpoint azurerm create `
  --name "azure-training-connection" `
  --azure-rm-service-principal-id "$SP_APP_ID" `
  --azure-rm-subscription-id "30b490cd-637c-4934-87a7-a38eba455adf" `
  --azure-rm-subscription-name "GFU-2026-01" `
  --azure-rm-tenant-id "$SP_TENANT" `
  --output table
```

Gib die Service Connection für alle Pipelines frei:

**Bash:**

```bash
# Service Connection für alle Pipelines freigeben
SC_ID=$(az devops service-endpoint list --output json | \
  jq -r '.[] | select(.name == "azure-training-connection") | .id')

az devops service-endpoint update \
  --id "$SC_ID" \
  --enable-for-all true \
  --output table
```

**PowerShell:**

```powershell
# Service Connection für alle Pipelines freigeben
$SC_ID = (az devops service-endpoint list --output json |
  jq -r '.[] | select(.name == "azure-training-connection") | .id')

az devops service-endpoint update `
  --id "$SC_ID" `
  --enable-for-all true `
  --output table
```

Du kannst die erstellte Service Connection im Browser unter **Project
Settings > Service connections** sehen.

### Schritt 3: Variable Group mit Key Vault erstellen

Jetzt verbinden wir den Key Vault mit Azure Pipelines. Dafür erstellen wir eine
**Variable Group mit Key-Vault-Verknüpfung**. Anders als bei der
`common-settings`-Gruppe aus Lab 04, wo die Werte direkt in der Gruppe
gespeichert werden, holt sich diese Gruppe die Werte zur Laufzeit aus dem Key
Vault.

Diese Variable Group muss über die Web-Oberfläche erstellt werden:

1. Gehe im linken Menü zu **Pipelines > Library**.
2. Klicke auf **"+ Variable group"**.
3. Name: `keyvault-secrets`.
4. Aktiviere den Toggle **"Link secrets from an Azure key vault as variables"**.
   Das Formular ändert sich jetzt und zeigt Felder für die Azure-Verbindung.
5. **Azure Subscription**: Wähle die Service Connection
   `azure-training-connection`, die du in Schritt 2 erstellt hast.
6. **Key Vault Name**: Wähle deinen Key Vault aus der Dropdown-Liste (z. B.
   `kv-training-...`). Azure DevOps prüft im Hintergrund, ob der Service
   Principal Zugriff auf den Vault hat.
7. Klicke auf **"+ Add"** und wähle die drei Secrets aus der Liste:
    - `database-password`
    - `api-key`
    - `connection-string`
8. Klicke auf **"Save"**.

Die Secrets werden **nicht** in Azure DevOps gespeichert - die Variable Group
merkt sich nur die Namen. Bei jedem Pipeline-Lauf werden die aktuellen Werte
live aus dem Key Vault geladen.

### Schritt 4: Pipeline mit Key Vault Secrets

Jetzt erstellen wir eine Pipeline, die auf die Secrets zugreift. Die Pipeline
demonstriert drei Aspekte:

1. Secrets werden automatisch maskiert - auch wenn du sie per `echo` ausgibst,
   erscheint im Log nur `***`.
2. Secrets können als Umgebungsvariablen an Skripte übergeben werden.
3. Du kannst die Länge eines Secrets prüfen, um sicherzustellen, dass es geladen
   wurde, ohne den Inhalt preiszugeben.

Ersetze den Inhalt von `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
      - master

# Beide Variable Groups einbinden: die reguläre aus Lab 04
# und die Key-Vault-verknüpfte aus diesem Lab.
variables:
  - group: common-settings
  - group: keyvault-secrets

pool:
  vmImage: 'ubuntu-22.04'

steps:
  - script: |
      echo "=== Secret-Test ==="
      echo "Datenbank-Passwort: $(database-password)"
      echo "API Key: $(api-key)"
      echo ""
      echo "WICHTIG: Die Werte oben werden als '***' maskiert!"
      echo "Azure Pipelines erkennt Secret-Variablen automatisch"
      echo "und verhindert, dass sie im Log sichtbar sind."
    displayName: 'Secrets anzeigen (werden maskiert)'

  - script: |
      echo "=== Sichere Verwendung von Secrets ==="
      # Secrets als Umgebungsvariable an ein Script übergeben
      # (sicherer als Inline-Verwendung)
      export DB_PASS="$(database-password)"
      export API_KEY="$(api-key)"

      # Simuliere eine Anwendungskonfiguration
      cat > /tmp/app-config.json << CONFIGEOF
      {
        "database": {
          "host": "myserver.database.windows.net",
          "port": 5432,
          "password": "***MASKED***"
        },
        "api": {
          "key": "***MASKED***"
        },
        "environment": "$(ENVIRONMENT)"
      }
      CONFIGEOF

      echo "Konfiguration erstellt (Secrets sind maskiert):"
      cat /tmp/app-config.json
    displayName: 'Secrets sicher verwenden'

  - script: |
      echo "=== Secret-Länge prüfen (ohne Inhalt preiszugeben) ==="
      SECRET="$(database-password)"
      echo "Länge des Datenbank-Passworts: ${#SECRET} Zeichen"

      if [ ${#SECRET} -gt 0 ]; then
        echo "Secret wurde erfolgreich geladen."
      else
        echo "FEHLER: Secret ist leer!"
        exit 1
      fi
    displayName: 'Secret-Validierung'
```

Committe und pushe die Änderung:

```bash
git add azure-pipelines.yml
git commit -m "Add Key Vault secrets integration"
git push origin master
```

Beim ersten Lauf der Pipeline mit einer neuen Variable Group oder Service
Connection muss die Nutzung einmalig genehmigt werden. Öffne den Pipeline-Run
im Browser. Du siehst eine Meldung wie *"This pipeline needs permission to
access a resource before this run can continue"*. Klicke auf **"View"** und
dann auf **"Permit"**, um den Zugriff zu erlauben. Bei allen weiteren Runs
entfällt dieser Schritt.

Beachte im Build-Log: Überall dort, wo ein Secret-Wert in der Ausgabe erscheinen
würde, zeigt Azure Pipelines stattdessen `***`. Diese Maskierung greift
automatisch für alle Variablen, die aus einer Key-Vault-verknüpften Variable
Group stammen. Du musst dafür nichts extra konfigurieren.

## Aufräumen

Der Key Vault und der Service Principal werden vom Trainer per Terraform
verwaltet und müssen nicht manuell gelöscht werden. Lösche nur die Ressourcen,
die du in diesem Lab selbst erstellt hast:

**Bash:**

```bash
# Service Connection löschen
SC_ID=$(az devops service-endpoint list --output json | \
  jq -r '.[] | select(.name == "azure-training-connection") | .id')
az devops service-endpoint delete --id "$SC_ID" --yes

# Variable Group "keyvault-secrets" in Azure DevOps löschen.
GROUP_ID=$(az pipelines variable-group list --query "[?name=='keyvault-secrets'].id" -o tsv)
az pipelines variable-group delete --group-id $GROUP_ID --yes
```

**PowerShell:**

```powershell
# Service Connection löschen
$SC_ID = (az devops service-endpoint list --output json |
  jq -r '.[] | select(.name == "azure-training-connection") | .id')
az devops service-endpoint delete --id "$SC_ID" --yes

# Variable Group "keyvault-secrets" in Azure DevOps löschen.
$GROUP_ID = (az pipelines variable-group list --query "[?name=='keyvault-secrets'].id" -o tsv)
az pipelines variable-group delete --group-id $GROUP_ID --yes
```
