% ==========================================================
% 算法名称：五次谐波法 (5th Harmonic Method)
% 适用场景：10kV中性点不接地/经消弧线圈接地系统 — 单相接地故障选线
% 适用模型：Distribution_Fault_Model.slx
% 课题方向：配电网单相接地故障选线方法研究
% ----------------------------------------------------------
% 算法思路：
%   消弧线圈的谐振补偿仅对工频 (50Hz) 零序电流有效，而对
%   高次谐波分量 (尤其是 5 次谐波 250Hz) 无法补偿。因此，
%   即使在消弧线圈接地系统中，故障线路的 5 次谐波零序电流幅值
%   仍远大于健全线路。本算法通过 FFT 提取 250Hz 分量并比较
%   各馈线的 5 次谐波零序电流幅值来识别故障线路。
% ==========================================================

%% 1. 运行 Simulink 仿真模型
disp('正在运行 Simulink 模型，请稍候...');
model_name = 'Distribution_Fault_Model';
addpath(fileparts(which(mfilename)));      % 确保公共函数可被找到
addpath(fullfile(fileparts(which(mfilename)), '..'));  % 将模型所在的上级目录加入搜索路径
out = sim(model_name);

%% 2. 定义分析参数
% 故障发生时刻: t_fault = 0.105s
% 窗口选取: 0.15s ~ 0.25s (故障后约 5 个工频周期的稳态段)
% 选取较长窗口的目的: 提高 FFT 的频率分辨率，使 250Hz 分量提取更准确
window_start = 0.150;
window_end   = 0.250;
fs = 20000;   % 采样频率 (Hz)，由仿真步长 5e-05s 决定: 1/5e-05 = 20000
f0 = 50;      % 系统基波频率 (Hz)，中国电网标准频率
f5 = 5 * f0;  % 五次谐波频率: 250Hz

%% 3. 调用公共数据提取函数
% 自动兼容 Timeseries / Structure / Array 三种 Simulink 输出格式
[time_axis, i1_data, i2_data, i3_data, i4_data, ~] = extract_simulation_data(out);

%% 4. 截取稳态时间窗口内的零序电流波形
idx = find(time_axis >= window_start & time_axis <= window_end);

i1_steady = i1_data(idx);   % 馈线 1 零序电流
i2_steady = i2_data(idx);   % 馈线 2 零序电流
i3_steady = i3_data(idx);   % 馈线 3 零序电流
i4_steady = i4_data(idx);   % 馈线 4 零序电流

%% 5. FFT 频谱分析：提取 250Hz (5次谐波) 分量
L = length(i1_steady);       % 截取信号的采样点数

% 对各馈线零序电流做快速傅里叶变换 (FFT)
I1_fft = fft(i1_steady);
I2_fft = fft(i2_steady);
I3_fft = fft(i3_steady);
I4_fft = fft(i4_steady);

% 计算 250Hz 在 FFT 结果中对应的数组索引
% 频率分辨率 df = fs / L，250Hz 对应的索引 = f5 / df + 1
target_idx = round(f5 * L / fs) + 1;

% 取出 250Hz 频点的幅值 (取模 / 归一化)
% 单边谱幅值 = 2 * |FFT结果| / L (直流分量不乘2)
amp5_1 = 2 * abs(I1_fft(target_idx)) / L;   % 馈线 1 五次谐波幅值
amp5_2 = 2 * abs(I2_fft(target_idx)) / L;   % 馈线 2 五次谐波幅值
amp5_3 = 2 * abs(I3_fft(target_idx)) / L;   % 馈线 3 五次谐波幅值
amp5_4 = 2 * abs(I4_fft(target_idx)) / L;   % 馈线 4 五次谐波幅值

fprintf('\n--- 各馈线零序电流五次谐波 (250Hz) 幅值 ---\n');
fprintf('馈线 1: %.6f A\n', amp5_1);
fprintf('馈线 2: %.6f A\n', amp5_2);
fprintf('馈线 3: %.6f A\n', amp5_3);
fprintf('馈线 4: %.6f A\n', amp5_4);

%% 6. 同步提取基波 (50Hz) 幅值，用于对比分析
target_idx_f0 = round(f0 * L / fs) + 1;
amp1_1 = 2 * abs(I1_fft(target_idx_f0)) / L;
amp1_2 = 2 * abs(I2_fft(target_idx_f0)) / L;
amp1_3 = 2 * abs(I3_fft(target_idx_f0)) / L;
amp1_4 = 2 * abs(I4_fft(target_idx_f0)) / L;

fprintf('\n--- 各馈线零序电流基波 (50Hz) 幅值 (参考) ---\n');
fprintf('馈线 1: %.6f A\n', amp1_1);
fprintf('馈线 2: %.6f A\n', amp1_2);
fprintf('馈线 3: %.6f A\n', amp1_3);
fprintf('馈线 4: %.6f A\n', amp1_4);

%% 7. 选线判据：寻找五次谐波零序电流幅值最大的馈线
amp5_array = [amp5_1, amp5_2, amp5_3, amp5_4];
[max_val, fault_line_index] = max(amp5_array);

%% 8. 门槛判据：将故障线的五次谐波幅值与健全线平均值对比，防止误判
% 若最大值与均值的比率低于阈值，说明各线路的谐波含量接近，可能无故障
ratio = max_val / mean(amp5_array);
fault_threshold = 2.0;  % 比率阈值 (可根据实际仿真情况调整)

fprintf('\n>>> 五次谐波法选线结果 <<<\n');
if ratio < fault_threshold
    fprintf('系统正常，未检测到明显故障 (比率 = %.2f，阈值 = %.2f)\n', ratio, fault_threshold);
else
    fprintf('判定故障线路为: 馈线 %d (比率 = %.2f)\n', fault_line_index, ratio);
end
fprintf('=================================\n');

%% 9. 绘制频谱对比图 (可视化各馈线的谐波分布)
figure('Name', '五次谐波法 - 频谱分析', 'NumberTitle', 'off', ...
       'Position', [100 100 900 600]);

% 计算频率轴 (单边谱)
freq_axis = (0:L-1) * fs / L;
half_L = floor(L / 2);

% 子图1~4: 各馈线的零序电流频谱
titles = {'馈线 1', '馈线 2', '馈线 3', '馈线 4'};
fft_data = {I1_fft, I2_fft, I3_fft, I4_fft};

for k = 1:4
    subplot(2, 2, k);
    amp_spectrum = 2 * abs(fft_data{k}(1:half_L)) / L;
    stem(freq_axis(1:half_L), amp_spectrum, 'b', 'MarkerSize', 2);
    hold on;
    % 标注 50Hz 基波位置
    xline(f0, '--r', '50Hz', 'LabelHorizontalAlignment', 'left', 'FontSize', 8);
    % 标注 250Hz 五次谐波位置
    xline(f5, '--m', '250Hz', 'LabelHorizontalAlignment', 'left', 'FontSize', 8);
    hold off;
    xlim([0 500]);   % 只显示 0~500Hz 范围
    xlabel('频率 (Hz)');
    ylabel('幅值 (A)');
    title(titles{k});
    grid on;
end
sgtitle('各馈线零序电流频谱 (五次谐波法)', 'FontSize', 14, 'FontWeight', 'bold');

%% 10. 绘制五次谐波幅值对比柱状图
figure('Name', '五次谐波法 - 选线结果', 'NumberTitle', 'off', ...
       'Position', [150 150 600 400]);
bar_colors = repmat([0.3 0.6 0.9], 4, 1);   % 默认蓝色
bar_colors(fault_line_index, :) = [0.9 0.2 0.2];  % 故障线路标红
b = bar(1:4, amp5_array, 0.6);
b.FaceColor = 'flat';
b.CData = bar_colors;
xlabel('馈线编号');
ylabel('五次谐波幅值 (A)');
title('各馈线五次谐波 (250Hz) 零序电流幅值对比');
set(gca, 'XTickLabel', {'馈线1', '馈线2', '馈线3', '馈线4'});
grid on;
% 在柱状图上标注数值
for k = 1:4
    text(k, amp5_array(k), sprintf('%.4f', amp5_array(k)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 9);
end

%% ========================================================================
%  【原理说明】五次谐波法在配电网单相接地故障选线中的应用
%  ========================================================================
%
%  一、基本原理
%  ----------
%  在中性点经消弧线圈接地的配电系统中，消弧线圈的作用是在发生单相接地
%  故障时，通过产生一个与故障点电容电流方向相反、大小接近的感性电流来
%  补偿电容电流，使故障点的残余电流减小，从而实现电弧自熄。
%
%  然而，消弧线圈的补偿作用仅针对工频 (50Hz) 基波分量有效。因为消弧
%  线圈是一个电感元件，其阻抗 Z_L = jωL，谐振补偿条件 (ωL = 1/ωC)
%  只在基波频率 ω_1 = 2π×50 处成立。对于 n 次谐波，消弧线圈的阻抗
%  变为 jnωL，而系统对地电容的阻抗变为 1/(jnωC)，两者不再满足谐振
%  条件，因此高次谐波分量不会被补偿。
%
%  在各次谐波中，五次谐波 (250Hz) 是含量最显著的低次谐波之一 (三次
%  谐波在三相对称系统中被三角形绕组消除)，因此被选作选线判据。
%
%  故障发生时，在五次谐波频率上：
%    - 非故障馈线的五次谐波零序电流 = 本线路自身在 250Hz 下的对地
%      电容电流 (较小)；
%    - 故障馈线的五次谐波零序电流 = 所有非故障馈线的五次谐波电容
%      电流之和 (较大)，且方向相反。
%
%  因此，与基波比幅法的原理类似，在五次谐波频率上，故障馈线的零序
%  电流幅值远大于健全馈线，且此结论不受消弧线圈补偿的影响。
%
%  二、FFT 提取五次谐波的方法
%  ----------
%  本算法使用快速傅里叶变换 (FFT) 提取 250Hz 分量的幅值：
%    (1) 选取故障后稳态时间窗口内的零序电流波形；
%    (2) 对各馈线零序电流做 FFT 变换，得到频域表示；
%    (3) 在 FFT 结果中定位 250Hz 对应的索引：k = round(f5 * L / fs) + 1；
%    (4) 取出该频点的复数模值，即为 250Hz 五次谐波分量的幅值；
%    (5) 归一化处理：单边谱幅值 = 2 * |FFT(k)| / L。
%
%  三、选线判据
%  ----------
%  计算各馈线零序电流的五次谐波幅值 A5_k (k = 1, 2, ..., n)：
%    - 五次谐波幅值最大的馈线即为故障馈线：fault = argmax(A5_k)
%    - 附加门槛判据：ratio = max(A5_k) / mean(A5_k)
%      当 ratio >= 阈值 (默认 2.0) 时，确认故障存在；
%      当 ratio < 阈值时，认为各馈线谐波含量接近，系统可能无故障。
%
%  四、优缺点
%  ----------
%  优点：
%    (1) 最大优势：不受消弧线圈补偿的影响。在消弧线圈接地系统中，
%        基波零序电流被大幅补偿，使比幅法失效，但五次谐波不受影响；
%    (2) 原理与比幅法类似，实现简单，计算量小；
%    (3) 灵敏度较高，尤其在消弧线圈过补偿或欠补偿状态下依然可靠；
%    (4) 不需要零序电压信号，仅依赖各馈线零序电流即可。
%
%  缺点：
%    (1) 五次谐波含量本身较小 (相对基波)，在高阻接地故障时信噪比
%        可能不足，影响选线可靠性；
%    (2) 当系统中存在非线性负载 (如变频器、整流器) 时，这些设备会
%        注入大量五次谐波电流，可能干扰选线判据；
%    (3) FFT 的频率分辨率受窗口长度影响，窗口过短时 250Hz 分量
%        的提取精度会下降；
%    (4) 当馈线数量较少或线路参数差异较大时，谐波分布不均，可能
%        降低选线准确率。
%
%  五、适用范围
%  ----------
%  主要适用于中性点经消弧线圈接地的配电系统，也适用于不接地系统。
%  在消弧线圈接地系统中，五次谐波法是对比幅法和比相法的重要补充，
%  三种方法结合使用可显著提高选线的可靠性和准确性。
%  在实际工程中，五次谐波法常作为微机保护装置中综合选线方案的一个
%  子判据，与其他方法联合决策。
%  ========================================================================
