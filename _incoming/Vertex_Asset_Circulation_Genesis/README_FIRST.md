# VERTEX ASSET CIRCULATION GENESIS

合言葉: **格納庫から母艦を育てる**

このパッケージは Fleet Genesis 骨太母艦へ増設するための、
VUR / VVE / Real Repository Bridge / VCRAS Hotline Boundary /
VCG Boundary / VUR Control Console / Main Console / Hyper Agent Chat /
Project Beacon / Design System / Reference VCell / Test Corpus を含む
ソース込みの初号大型ユニット群です。

## 時間軸
- VUR = 蓄積された過去・再利用可能部品
- VVE = 未確定の未来
- Real Repository = 確定した現在
- Git = 確定後の履歴
- GitHub = 外部共有/保管

## 標準経路
VUR -> VVE -> Validate/Simulate -> Human Gate -> Promote -> Real Repository -> Git

## 重要原則
1. VUR は作業ツリーではない。
2. VUR から Real Repository へ直接書き込まない。
3. 外部/旧資産は STAGING / QUARANTINE から入る。
4. VCell / Unit / Pack は Lineage と Relation を保持する。
5. VVE は Real Repository をコピーするのではなく Overlay/Future Tree を作る。
6. 本番更新は Live Edit ではなく Shadow Validation -> Safe Promote。
7. 既存 Fleet Genesis Canonical Architecture を置換しない。正式進化として接続する。
8. Owner Hotline と一般 Client の接続権限は分離する。
9. UI は SF Fantasy RPG Fleet Console を基準とする。
10. Project Beacon は「パスを開く」のではなく「Projectへ帰還する」。

## インストール
PowerShell:
    Set-Location 'G:\Vertex Protocol\Vertex Project'
    Expand-Archive '<downloaded zip>' '.\_incoming\Vertex_Asset_Circulation_Genesis' -Force
    .\_incoming\Vertex_Asset_Circulation_Genesis\INSTALL_VERTEX_ASSET_CIRCULATION.ps1

既存 VUR がある場合はバックアップしてから統合します。

## UI Preview
    .\VUR\CONTROL\preview\START_PREVIEW.ps1

ブラウザで http://127.0.0.1:8787 を開くと、
依存ライブラリなしのスタンドアロン Console Preview が表示されます。
