[日本語](prior-art.md) | [English](prior-art.en.md)

# 先行調査

ここにある主張は、Logic 12.3.1 / macOS 27 で再現し、`Research/experiments/` に記録するまでは未検証として扱います。

## evilsocket — Reverse Engineering the Apple MultiPeer Connectivity Framework（2022-10-20）

- URL: https://www.evilsocket.net/2022/10/20/Reverse-Engineering-the-Apple-MultiPeer-Connectivity-Framework
- PoC: https://github.com/evilsocket/mpcfw（Python。mdns、tcp、stun、"ospf" モジュール）。**ライセンスファイルがありません**。参考として読むだけにし、このリポジトリへコードをコピーしないでください。
- Logic Remote の通信を起点にした調査です。以下は記事の主張であり、この調査記録ではいずれも未検証です。
  - TCP サーバーのポートは起動ごとにランダムに決まり、mDNS で告知されます。ピア ID はランダムな64ビット整数の base36 表記です（こちらで観測したインスタンス名 `174jnk4ko0l8w` と形式が一致します）。
  - TCP ヘッダーは、2バイトのシグネチャ（Hello/Ack/Accept/Invitation/InviteResponse/ClientData）、4バイトのシーケンス番号＋フラグ、2バイトのペイロードサイズ、4バイトの CRC32、意味不明の4バイト定数からなります。
  - ペイロードは入れ子のバイナリ plist（`bplist00`）です。`MCNearbyServiceInviteIDKey`、`MCNearbyServiceSenderPeerIDKey`、`MCNearbyServiceConnectionDataKey` などのキーを使います。
  - Apple 独自の STUN/ICE 交換後、セッションデータを UDP で送ります。内部パケットの形式には、シグネチャバイト 0xC1、チャネル ID、CRC16/ARC、送信元・受信先のピア ID が含まれます。
  - 認可の根拠はピアのホスト名だけです。
  - Logic のアプリケーションメッセージ形式は**記載されていません**。

## Alban Diquet — "It Just (Net)Works", HITB KUL 2014

- https://archive.conference.hitb.org/hitbsecconf2014kul/sessions/it-just-networks-the-truth-about-apples-multipeer-connectivity-framework/
- MPC の全体像を扱う分析です。

## Logic OSC / TouchOSC

- https://hardware.hexler.net/touchosc/manual/setup-logic — TouchOSC を Logic のコントロールサーフェスとして使う設定です。Logic はポート 7000 で OSC を受信します。
- https://cycling74.com/forums/controlling-logic-pro-x-through-osc

## FradSer — mcp-server-apple-events

[適合性の調査記録](mcp-apple-events-reference.md)でcommitを固定し、ソースを確認しました。Reminders/Calendarのnative CLIをMCPで公開する構成は参考になります。Logicのprivate AppleEvent送信や状態取得の実装は含まれません。日英の記録には構成図、再利用できる境界、結果・権限・versionの違いを整理しています。
