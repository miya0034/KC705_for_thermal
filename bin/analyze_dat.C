#include <iostream>
#include <fstream>
#include "TH1D.h"
#include "TH1I.h"
#include "TH2D.h"
#include "TCanvas.h"
#include "TStyle.h"

void analyze_dat(const char* filename = "sitcp_data.dat")
{
    // 1 LSB = 2 ns
    const double LSB_NS = 2.0;

    // ---- ヒストグラム定義 ----
    // Δt ヒストグラム（0〜1000 ns を 1000 bin）範囲は適宜調整
    TH1D* h_dt = new TH1D("h_dt",
                          "Time difference;#Delta t [ns];Counts",
                          1000, 0.0, 1000.0);

    // ID の分布ヒストグラム（ID は 0〜255 と仮定）
    TH1I* h_id = new TH1I("h_id",
                          "ID distribution;ID;Counts",
                          256, -0.5, 255.5);

    // ID vs Δt の 2D ヒストグラム（必要なら見る）
    TH2D* h2_id_dt = new TH2D("h2_id_dt",
                              "ID vs #Delta t;ID;#Delta t [ns]",
                              256, -0.5, 255.5,
                              1000, 0.0, 1000.0);

    // ---- dat ファイルをバイナリで開く ----
    std::ifstream fin(filename, std::ios::binary);
    if (!fin.is_open()) {
        std::cerr << "Cannot open file: " << filename << std::endl;
        return;
    }

    const int REC_SIZE = 8;          // 1 レコード = 8 バイト
    unsigned char buf[REC_SIZE];     // 読み取りバッファ

    bool first = true;
    unsigned long long prev_ts = 0;          // 前イベントの 56bit 時間情報
    const unsigned long long rollover = 1ULL << 56;  // 7 バイト = 56 bit

    unsigned long long event_count = 0;
    unsigned long long used_pairs  = 0;

    while (true) {
        fin.read(reinterpret_cast<char*>(buf), REC_SIZE);
        std::streamsize nread = fin.gcount();
        if (nread == 0) {
            // EOF
            break;
        }
        if (nread < REC_SIZE) {
            std::cerr << "Warning: last record is incomplete ("
                      << nread << " bytes). Ignored." << std::endl;
            break;
        }

        // buf[0] が ID
        unsigned char id = buf[0];

        // buf[1]〜buf[7] が 7 バイトの時間情報 (big endian と仮定)
        unsigned long long ts = 0;
        for (int i = 0; i < 7; ++i) {
            ts = (ts << 8) | static_cast<unsigned long long>(buf[1 + i]);
        }

        // ID は毎イベントごとにヒストグラムへ積む
        h_id->Fill(static_cast<int>(id));

        if (!first) {
            // 差分 ΔT = T_n - T_{n-1}
            long long diff = static_cast<long long>(ts) -
                             static_cast<long long>(prev_ts);

            // カウンタのロールオーバ補正が必要な場合
            if (diff < 0) {
                diff += static_cast<long long>(rollover);
            }

            // 実時間 [ns] に変換: Δt[ns] = diff * 2 ns
            double dt_ns = static_cast<double>(diff) * LSB_NS;

            // Δt ヒストグラムへ
            h_dt->Fill(dt_ns);

            // 2D ヒストグラムへ (ID vs Δt)
            h2_id_dt->Fill(static_cast<double>(id), dt_ns);

            ++used_pairs;
        } else {
            first = false;  // 最初のイベントは差が取れないのでスキップ
        }

        prev_ts = ts;
        ++event_count;
    }

    fin.close();

    std::cout << "Total events  : " << event_count << std::endl;
    std::cout << "Used pairs    : " << used_pairs  << std::endl;

    // ---- 描画 ----
    gStyle->SetOptStat(1110);

    // Δt と ID の 1D ヒストグラムを並べて表示
    TCanvas* c1 = new TCanvas("c1", "dt and ID", 1200, 600);
    c1->Divide(2, 1);

    // 左: Δt ヒストグラム (y 軸 log)
    c1->cd(1);
    gPad->SetLogy();
    h_dt->Draw();

    // 右: ID ヒストグラム
    c1->cd(2);
    h_id->Draw();

    // ID vs Δt の 2D ヒストグラム（必要なら別キャンバスで）
    TCanvas* c2 = new TCanvas("c2", "ID vs dt", 800, 600);
    gPad->SetLogz();          // カウント数を log 表示したい場合
    h2_id_dt->Draw("COLZ");
}