#!/bin/bash
# Cleanup-Script für alle Azure Pipeline Training Labs
# Löscht alle erstellten Azure-Ressourcen
#
# Verwendung: bash cleanup-all.sh
#
# WARNUNG: Dieses Script löscht unwiderruflich Ressourcen!

set -e

echo "============================================"
echo "  Azure Pipeline Training - Cleanup"
echo "============================================"
echo ""
echo "Dieses Script löscht alle Azure-Ressourcen,"
echo "die während des Trainings erstellt wurden."
echo ""
read -p "Fortfahren? (ja/nein): " CONFIRM
if [ "$CONFIRM" != "ja" ]; then
  echo "Abgebrochen."
  exit 0
fi

SUBSCRIPTION="30b490cd-637c-4934-87a7-a38eba455adf"
RG="rg-pipeline-training"

echo ""
echo "Subscription: $SUBSCRIPTION"
az account set --subscription "$SUBSCRIPTION"

# 1. App Services und Pläne löschen
echo ""
echo "=== App Services löschen ==="
APPS=$(az webapp list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null || true)
if [ -n "$APPS" ]; then
  for app in $APPS; do
    echo "  Lösche Web App: $app"
    az webapp delete --name "$app" --resource-group "$RG" 2>/dev/null || true
  done
fi

PLANS=$(az appservice plan list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null || true)
if [ -n "$PLANS" ]; then
  for plan in $PLANS; do
    echo "  Lösche App Service Plan: $plan"
    az appservice plan delete --name "$plan" --resource-group "$RG" --yes 2>/dev/null || true
  done
fi

# 2. Container Registries löschen
echo ""
echo "=== Container Registries löschen ==="
ACRS=$(az acr list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null || true)
if [ -n "$ACRS" ]; then
  for acr in $ACRS; do
    echo "  Lösche ACR: $acr"
    az acr delete --name "$acr" --resource-group "$RG" --yes 2>/dev/null || true
  done
fi

# 3. Key Vaults löschen
echo ""
echo "=== Key Vaults löschen ==="
KVS=$(az keyvault list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null || true)
if [ -n "$KVS" ]; then
  for kv in $KVS; do
    echo "  Lösche Key Vault: $kv"
    az keyvault delete --name "$kv" --resource-group "$RG" 2>/dev/null || true
    echo "  Purge Key Vault: $kv"
    az keyvault purge --name "$kv" --location westeurope 2>/dev/null || true
  done
fi

# 4. Storage Accounts löschen
echo ""
echo "=== Storage Accounts löschen ==="
STORAGES=$(az storage account list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null || true)
if [ -n "$STORAGES" ]; then
  for sa in $STORAGES; do
    echo "  Lösche Storage Account: $sa"
    az storage account delete --name "$sa" --resource-group "$RG" --yes 2>/dev/null || true
  done
fi

# 5. Verbleibende Ressourcen in der RG anzeigen
echo ""
echo "=== Verbleibende Ressourcen ==="
REMAINING=$(az resource list --resource-group "$RG" --query "[].{Name:name, Type:type}" -o table 2>/dev/null || true)
if [ -n "$REMAINING" ] && [ "$(echo "$REMAINING" | wc -l)" -gt 2 ]; then
  echo "Folgende Ressourcen sind noch vorhanden:"
  echo "$REMAINING"
  echo ""
  read -p "Resource Group '$RG' komplett löschen? (ja/nein): " DELETE_RG
  if [ "$DELETE_RG" = "ja" ]; then
    echo "Lösche Resource Group: $RG"
    az group delete --name "$RG" --yes --no-wait
    echo "Löschung wurde gestartet (läuft im Hintergrund)."
  fi
else
  echo "Keine verbleibenden Ressourcen."
  echo ""
  read -p "Leere Resource Group '$RG' löschen? (ja/nein): " DELETE_RG
  if [ "$DELETE_RG" = "ja" ]; then
    az group delete --name "$RG" --yes --no-wait
    echo "Resource Group wird gelöscht."
  fi
fi

# 6. Von Terraform/Bicep erstellte Resource Groups
echo ""
echo "=== Terraform/Bicep Resource Groups ==="
EXTRA_RGS=$(az group list --query "[?starts_with(name, 'rg-training-app')].name" -o tsv 2>/dev/null || true)
if [ -n "$EXTRA_RGS" ]; then
  for rg in $EXTRA_RGS; do
    echo "  Lösche Resource Group: $rg"
    az group delete --name "$rg" --yes --no-wait 2>/dev/null || true
  done
fi

echo ""
echo "============================================"
echo "  Cleanup abgeschlossen"
echo "============================================"
echo ""
echo "Hinweis: Einige Löschungen laufen noch im Hintergrund."
echo "Prüfe in einigen Minuten im Azure Portal, ob alles gelöscht ist."
