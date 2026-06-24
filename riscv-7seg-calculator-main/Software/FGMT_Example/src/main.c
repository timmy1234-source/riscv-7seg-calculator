#include <stdint.h>
#include "io.h"

#define GPIO_BASE 0xfffffec0

void delay(int count) { while(count--); }

// 移除除法，純減法拆解數字
void split_digits(int val, int *d0, int *d1, int *is_neg) {
    if (val < 0) { *is_neg = 1; val = -val; } else { *is_neg = 0; }
    int temp = (val > 99) ? 99 : val;
    *d1 = 0;
    while (temp >= 10) { temp -= 10; *d1 += 1; }
    *d0 = temp;
}

unsigned int get_seg_code(int val) {
    unsigned int codes[] = {0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9};
    if (val >= 0 && val <= 9) return codes[val];
    return 0x0;
}

int main(void) {
    out32(GPIO_BASE + 0x08, 0x001FFFF0);

    int A = 0, B = 0, op = 0;
    int display_mode = 3;

    while (1) {
        unsigned int btn = in32(GPIO_BASE + 0x00) & 0x1F;

        // --- 功能按鈕區 ---
        if (btn & 0x01) { display_mode = 0; A++; if(A > 99) A = 99; delay(200000); }
        if (btn & 0x02) { display_mode = 1; B++; if(B > 99) B = 99; delay(200000); }
        if (btn & 0x04) { op = !op; display_mode = 3; delay(500000); }

        // 歸零鍵測試：如果你發現按 0x08 沒反應，請改為 0x10
        if (btn & 0x08) { A = 0; B = 0; op = 0; display_mode = 3; delay(500000); }
        if (btn & 0x10) { A = 0; B = 0; op = 0; display_mode = 3; delay(500000); }

        // --- 顯示運算區 ---
        int disp_val = (display_mode == 0) ? A :
                       (display_mode == 1) ? B :
                       ((op == 0) ? (A + B) : (A - B));

        int d0, d1, neg;
        split_digits(disp_val, &d0, &d1, &neg);

        unsigned int seg_d0 = get_seg_code(d0);
        // 若為負數顯示 0xC
        unsigned int seg_d1 = (neg) ? 0xC : get_seg_code(d1);

        out32(GPIO_BASE + 0x04, (seg_d0 << 5) | (seg_d1 << 9));
    }
}
