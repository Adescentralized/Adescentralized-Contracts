#!/bin/bash

# Script para testar todas as funcionalidades do contrato AdVault
# Este script assume que você já tem as contas configuradas (admin, advertiser, publisher, viewer, verifier)

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configurações
NETWORK="testnet"
ADVAULT_CONTRACT="CC2DKPUF6RFI3MQJBOWREWGZPJGLHNPYFSNGSF27EX5RE2QWT5I55VJL"
TOKEN_CONTRACT="CDZBPW57N5B64XJMNOP3FPFDUXO3LFYEWOY2WJYA4EI6WBDMSXNESNL6"
VERIFIER_REGISTRY_CONTRACT="CDYDD4IPTAF2AQ36XBT2X4JYRIHKEWDKCGFWTLYUKP4ESSGSUAEM6ZBC"

# Função para imprimir mensagens coloridas
print_step() {
    echo -e "${BLUE}🔧 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Função para executar comandos stellar e capturar erros
run_stellar_command() {
    local description="$1"
    shift
    print_step "$description"
    
    if output=$(stellar "$@" 2>&1); then
        print_success "$description - Concluído"
        echo "$output"
        return 0
    else
        print_error "$description - Falhou"
        echo "$output"
        return 1
    fi
}

echo -e "${GREEN}🚀 Testando AdVault Contract${NC}"
echo "=================================="

# 1. Inicializar o contrato
print_step "1. Inicializando o contrato AdVault"
run_stellar_command "Inicialização" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- init \
    --admin admin \
    --token $TOKEN_CONTRACT \
    --verifier_registry $VERIFIER_REGISTRY_CONTRACT \
    --price_per_event 10000000 \
    --split_publisher_bps 6000 \
    --split_viewer_bps 3000 \
    --fee_bps 1000

echo ""

# 2. Verificar configurações
print_step "2. Verificando configurações do contrato"
run_stellar_command "Get Config" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_config

echo ""

# 3. Verificar se o protocolo está pausado
print_step "3. Verificando status do protocolo"
run_stellar_command "Is Protocol Paused" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- is_protocol_paused

echo ""

# 4. Criar uma campanha
print_step "4. Criando uma campanha de teste"
CAMPAIGN_ID=$(echo -n "test_campaign_$(date +%s)" | sha256sum | cut -d' ' -f1)
CAMPAIGN_ID_HEX="$(printf '%064s' $CAMPAIGN_ID | tr ' ' '0')"

echo "Campaign ID: $CAMPAIGN_ID_HEX"

run_stellar_command "Create Campaign" contract invoke --network $NETWORK --source advertiser \
    --id $ADVAULT_CONTRACT -- create_campaign \
    --campaign_id "$CAMPAIGN_ID_HEX" \
    --advertiser advertiser \
    --initial_deposit 100000000

echo ""

# 5. Verificar a campanha criada
print_step "5. Verificando a campanha criada"
run_stellar_command "Get Campaign" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id "$CAMPAIGN_ID_HEX"

echo ""

# 6. Fazer um depósito adicional na campanha
print_step "6. Fazendo depósito adicional na campanha"
run_stellar_command "Deposit" contract invoke --network $NETWORK --source advertiser \
    --id $ADVAULT_CONTRACT -- deposit \
    --campaign_id "$CAMPAIGN_ID_HEX" \
    --from advertiser \
    --amount 50000000

echo ""

# 7. Verificar a campanha após depósito
print_step "7. Verificando a campanha após depósito"
run_stellar_command "Get Campaign After Deposit" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id "$CAMPAIGN_ID_HEX"

echo ""

# 8. Testar submit_event (requer verifier autorizado)
print_step "8. Testando submit_event"
EVENT_ID=$(echo -n "test_event_$(date +%s)" | sha256sum | cut -d' ' -f1 | head -c 64)
EVENT_ID_BYTES32="0x${EVENT_ID}"
NONCE=$(echo -n "nonce_$(date +%s)" | sha256sum | cut -d' ' -f1 | head -c 64)
NONCE_BYTES32="0x${NONCE}"

echo "Event ID: $EVENT_ID_BYTES32"
echo "Nonce: $NONCE_BYTES32"

# Nota: Este comando pode falhar se o verifier não estiver autorizado
print_warning "Este comando pode falhar se o verifier não estiver autorizado no VerifierRegistry"
run_stellar_command "Submit Event" contract invoke --network $NETWORK --source verifier \
    --id $ADVAULT_CONTRACT -- submit_event \
    --att "{
        \"event_id\": \"$EVENT_ID_BYTES32\",
        \"campaign_id\": \"$CAMPAIGN_ID_BYTES32\", 
        \"publisher\": \"publisher\",
        \"viewer\": \"viewer\",
        \"event_kind\": \"click\",
        \"timestamp\": $(date +%s),
        \"nonce\": \"$NONCE_BYTES32\"
    }" \
    --verifier verifier || true

echo ""

# 9. Verificar a campanha após evento (se funcionou)
print_step "9. Verificando a campanha após evento"
run_stellar_command "Get Campaign After Event" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id $CAMPAIGN_ID_BYTES32

echo ""

# 10. Testar funções administrativas
print_step "10. Testando funções administrativas"

print_step "10.1. Pausando o protocolo"
run_stellar_command "Pause Protocol" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- pause_protocol

print_step "10.2. Verificando se está pausado"
run_stellar_command "Is Paused After Pause" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- is_protocol_paused

print_step "10.3. Despausando o protocolo"
run_stellar_command "Unpause Protocol" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- unpause_protocol

print_step "10.4. Alterando preço por evento"
run_stellar_command "Set Price Per Event" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- set_price_per_event \
    --new_price 15000000

print_step "10.5. Alterando splits"
run_stellar_command "Set Splits" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- set_splits \
    --pub_bps 5500 \
    --view_bps 3500

print_step "10.6. Alterando taxa do protocolo"
run_stellar_command "Set Fee BPS" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- set_fee_bps \
    --new_fee 1200

echo ""

# 11. Verificar configurações após mudanças
print_step "11. Verificando configurações após mudanças"
run_stellar_command "Get Config After Changes" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_config

echo ""

# 12. Fechar campanha e fazer refund
print_step "12. Fechando campanha e fazendo refund"

print_step "12.1. Fechando campanha"
run_stellar_command "Close Campaign" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- close_campaign \
    --campaign_id $CAMPAIGN_ID_BYTES32 \
    --reason "test_completed"

print_step "12.2. Fazendo refund do valor não gasto"
run_stellar_command "Refund Unspent" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- refund_unspent \
    --campaign_id $CAMPAIGN_ID_BYTES32 \
    --to advertiser

echo ""

# 13. Verificar campanha após fechamento
print_step "13. Verificando campanha após fechamento"
run_stellar_command "Get Campaign After Close" contract invoke --network $NETWORK --source admin \
    --id $ADVAULT_CONTRACT -- get_campaign \
    --campaign_id $CAMPAIGN_ID_BYTES32

echo ""
echo -e "${GREEN}🎉 Teste do AdVault Contract concluído!${NC}"
echo "=================================="
