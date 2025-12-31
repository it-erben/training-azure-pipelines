# Trainer-Hinweise

Die folgenden Befehle werden im Verzeichnis `internal/azure-setup` ausgeführt,
in dem die Terraform-Konfiguration liegt.

## Teilnehmer-Zugangsdaten (AD-Accounts) abrufen

```bash
terraform output -json participant_credentials
```

Gibt pro Teilnehmer `username` und `password` aus.

## Service-Principal-Zugangsdaten abrufen

```bash
terraform output -json service_principal_credentials
```

Gibt pro Teilnehmer `app_id`, `password` und `tenant_id` aus. Diese drei
Werte brauchen die Teilnehmer in Schritt 2, um die Service Connection
anzulegen.

## Kompakte Übersicht

```bash
terraform output -json participant_summary
```

Zeigt pro Teilnehmer: Username, DevOps-Projekt, App Service, Key-Vault-Name
und Service-Principal-App-ID (ohne Secrets).
