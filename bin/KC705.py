#!/usr/bin/env python3
import socket

# ===== ユーザー環境に合わせてここを書き換える =====
SITCP_IP   = "192.168.10.16"      # SiTCP ボードの IP
SITCP_PORT = 24                   # ユーザデータ用 TCP ポート
BUF_SIZE   = 4096                 # 1回の recv サイズ（任意）
FRAME_SIZE = 12                   # 2 header + 8 data + 2 footer
DAT_FILE   = "sitcp_data.dat"     # 出力バイナリファイル名

# ヘッダ/フッタの既知パターン: 8'h55, 8'hAA の 2バイト
EXPECTED_HEADER = b"\xAA\x55"
EXPECTED_FOOTER = b"\x55\xAA"

# 取得したい「有効イベント数」を 1000 に固定
MAX_EVENTS = 1000
# =====================================================

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    print(f"Connecting to {SITCP_IP}:{SITCP_PORT} ...")
    sock.connect((SITCP_IP, SITCP_PORT))
    print("Connected.")

    buffer = b""

    total_frames   = 0  # 12バイトフレームとして解釈した全フレーム数
    good_frames    = 0  # ヘッダ/フッタ正常で .dat に書いたフレーム数
    bad_header     = 0  # ヘッダ不一致のフレーム数
    bad_footer     = 0  # フッタ不一致のフレーム数

    done = False  # MAX_EVENTS に到達したかどうか

    # dat ファイルをバイナリ書き込みでオープン
    with sock, open(DAT_FILE, "wb") as fout:
        try:
            while not done:
                chunk = sock.recv(BUF_SIZE)
                if not chunk:
                    print("Connection closed by peer.")
                    break

                buffer += chunk

                # バッファに 1フレーム分以上あれば処理
                while len(buffer) >= FRAME_SIZE and not done:
                    frame = buffer[:FRAME_SIZE]
                    buffer = buffer[FRAME_SIZE:]

                    header = frame[0:2]
                    data   = frame[2:10]   # 8 bytes = 1B ID + 7B time
                    footer = frame[10:12]

                    total_frames += 1

                    # 8バイトデータの分解
                    ch_id    = data[0:1]   # bytes 型のまま 1バイト
                    ts_bytes = data[1:8]   # 7バイト時間情報

                    # ヘッダ・フッタのチェック
                    header_ok = (header == EXPECTED_HEADER)
                    footer_ok = (footer == EXPECTED_FOOTER)

                    if not header_ok:
                        bad_header += 1
                    if not footer_ok:
                        bad_footer += 1

                    # ヘッダ・フッタを標準出力に表示
                    print(
                        f"Frame {total_frames - 1}: "
                        f"header={header.hex()} (OK={header_ok}), "
                        f"footer={footer.hex()} (OK={footer_ok})"
                    )

                    # ヘッダ/フッタともに正しければ .dat に書く
                    if header_ok and footer_ok:
                        fout.write(ch_id + ts_bytes)
                        good_frames += 1

                        # 有効イベントが MAX_EVENTS に到達したら終了
                        if good_frames >= MAX_EVENTS:
                            done = True
                            break

        finally:
            if buffer:
                print(
                    f"Warning: {len(buffer)} bytes remain that do not "
                    f"form a full frame. Ignored."
                )

    # 集計
    invalid_frames = total_frames - good_frames

    print("==== Summary ====")
    print(f"Total frames (12B parsed) : {total_frames}")
    print(f"Good frames (used)        : {good_frames}")
    print(f"Frames with bad header    : {bad_header}")
    print(f"Frames with bad footer    : {bad_footer}")
    print(f"Invalid frames (total-bad): {invalid_frames}")
    print(f"Binary data written to    : {DAT_FILE}")

    # 損失率の計算
    if total_frames > 0:
        loss_rate = invalid_frames / total_frames
        print(f"Loss rate (invalid/total): {loss_rate:.3%}")
    else:
        print("No frames were parsed; loss rate is undefined.")

if __name__ == "__main__":
    main()