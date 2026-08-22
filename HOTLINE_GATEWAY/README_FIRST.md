# VERTEX HOTLINE NERVE GATEWAY PACK

目的:
- VCG Gate
- VCRAS Hotline
- Hyper Agent Mission Router
- ARD / VVE / Repository Relation Bridge
- VUR read bridge
- Audit/Event Bus
- Owner-only local runtime

合言葉:
**格納庫から母艦を育てる**

対応:
- Python 3.9+
- 外部Python依存なし
- Windows / PowerShell
- Fleet Genesis 母艦:
  G:\Vertex Protocol\Vertex Project

## 重要
このPackは「ChatGPTが勝手にPCへ入る仕組み」ではありません。
母艦側に Owner-only Gateway Runtime を構築し、
許可された Capability のみを VCG が実行できるようにします。
外部ChatGPT接続は VCRAS adapter / 正式Connector層からこのGatewayへ入れる設計です。

## 標準経路
ChatGPT / External Controller
        ↓
     VCRAS
        ↓
      VCG
        ↓
 Hyper Agent Router
        ↓
      ARD
   ┌────┼────┐
   ↓    ↓    ↓
  VUR   VVE   Repository

Real Repositoryへの直接書込み:
**禁止**

書込み可能:
- VVE
- VUR inbound/staging
- Audit/Event logs

## 初期 Capability
READ_VUR
READ_VVE
WRITE_VVE
READ_ARD_GRAPH
QUERY_RELATIONS
GIT_INSPECT
BUILD
TEST
MISSION_SUBMIT

## Build
PowerShell:
    .\BUILD.ps1

## Test
    .\TEST.ps1

## Demo
    .\RUN_DEMO.ps1

## Install to mothership
    .\INSTALL.ps1

## Run Gateway
    G:\Vertex Protocol\Vertex Project\HOTLINE_GATEWAY\RUN_GATEWAY.ps1

Default local endpoint:
    http://127.0.0.1:8765

Health:
    GET /health

Capability query:
    GET /capabilities

Mission submit:
    POST /mission
