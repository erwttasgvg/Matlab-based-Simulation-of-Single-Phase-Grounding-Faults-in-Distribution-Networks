% =========================================================================
% 脚本名称：五次谐波法 — 准确性批量测试
% 文件名：  Fifth_Harmonic_Accuracy_Analysis.m
% 适用模型：Distribution_Fault_Model.slx
% -------------------------------------------------------------------------
% 功能说明：
%   自动遍历多种故障电阻、故障初相角、消弧线圈补偿度的组合工况，
%   对每种工况运行仿真并执行五次谐波法选线判据，统计算法的选线准确率。
%
% 核心原理：
%   消弧线圈仅补偿工频 (50Hz) 零序电流，对五次谐波 (250Hz) 无补偿作用。
%   故障馈线在 250Hz 上的零序电流幅值 = 全系统非故障馈线的五次谐波电容
%   电流之和，远大于健全馈线。
%   判据：通过 FFT 提取 250Hz 分量，幅值最大的馈线 = 故障馈线。
% =========================================================================

clear; clc; close all;

%% ======================== 参数定义 ========================

model_name = 'Distribution_Fault_Model';
true_fault_line = 2;       % 已验证的故障馈线编号（馈线 2）
num_feeders = 4;           % 馈线总数

% --- 故障电阻 (Ω) ---
Rf_list = [0.000001, 1, 10, 50, 100, 500, 1000];

% --- 故障初相角 (度) 及对应的 SwitchTimes (s) ---
alpha_list = [0, 30, 45, 60, 90, 150];
t_base = 0.1;
T_period = 1/50;
switch_times_list = t_base + (alpha_list / 360) * T_period;

% --- 消弧线圈补偿度 ---
L_full = 1.0262;
compensation_labels = {'欠补偿(v=+10%)', '全补偿(v=0%)', '过补偿(v=-10%)'};
L_coil_list = [L_full / 0.90, L_full, L_full / 1.10];

% --- 五次谐波法参数 ---
fault_threshold = 2.0;     % 比率门槛阈值
steady_delay = 0.045;      % 故障后等待时间 (s)
steady_duration = 0.100;   % 稳态窗口持续时间 (s)，约 5 个工频周期（提高 FFT 频率分辨率）
fs = 20000;                % 采样频率 (Hz)
f0 = 50;                   % 基波频率 (Hz)
f5 = 5 * f0;               % 五次谐波频率 250Hz

% --- 结果存储 ---
total_cases = length(L_coil_list) * length(Rf_list) * length(alpha_list);
results = struct();
results.compensation = cell(total_cases, 1);
results.Rf = zeros(total_cases, 1);
results.alpha = zeros(total_cases, 1);
results.detected_line = zeros(total_cases, 1);
results.is_correct = false(total_cases, 1);
results.amp5_values = zeros(total_cases, num_feeders);
results.ratio = zeros(total_cases, 1);

%% ======================== 加载模型 ========================

fprintf('========================================\n');
fprintf('  五次谐波法准确性批量测试 开始\n');
fprintf('  总工况数: %d\n', total_cases);
fprintf('========================================\n\n');

addpath(fileparts(which(mfilename)));
addpath(fullfile(fileparts(which(mfilename)), '..'));
load_system(model_name);

%% ======================== 批量仿真循环 ========================

case_idx = 0;
tic;

for i_comp = 1:length(L_coil_list)
    L_val = L_coil_list(i_comp);
    set_param([model_name, '/Series RLC Branch2'], 'Inductance', num2str(L_val, '%.6f'));
    
    for i_rf = 1:length(Rf_list)
        Rf_val = Rf_list(i_rf);
        set_param([model_name, '/Grounding_Fault'], 'FaultResistance', num2str(Rf_val));
        
        for i_alpha = 1:length(alpha_list)
            case_idx = case_idx + 1;
            t_fault = switch_times_list(i_alpha);
            set_param([model_name, '/Grounding_Fault'], 'SwitchTimes', num2str(t_fault, '%.6f'));
            
            % --- 运行仿真 ---
            try
                out = sim(model_name, 'SrcWorkspace', 'current');
                [time_axis, i1, i2, i3, i4, ~] = extract_simulation_data(out);
                
                % --- 截取稳态窗口 ---
                win_start = t_fault + steady_delay;
                win_end   = win_start + steady_duration;
                idx = (time_axis >= win_start & time_axis <= win_end);
                
                i1_seg = i1(idx);
                i2_seg = i2(idx);
                i3_seg = i3(idx);
                i4_seg = i4(idx);
                L = length(i1_seg);
                
                % --- FFT 提取 250Hz 五次谐波分量 ---
                I1_fft = fft(i1_seg);
                I2_fft = fft(i2_seg);
                I3_fft = fft(i3_seg);
                I4_fft = fft(i4_seg);
                
                target_idx = round(f5 * L / fs) + 1;
                
                amp5 = [2*abs(I1_fft(target_idx))/L, ...
                        2*abs(I2_fft(target_idx))/L, ...
                        2*abs(I3_fft(target_idx))/L, ...
                        2*abs(I4_fft(target_idx))/L];
                
                % --- 选线判据：五次谐波幅值最大 + 比率门槛 ---
                [max_amp5, detected] = max(amp5);
                ratio_val = max_amp5 / mean(amp5);
                
                if ratio_val < fault_threshold
                    detected = 0;   % 未达门槛，判为无故障
                end
                
            catch ME
                fprintf('  [错误] 工况 %d: %s\n', case_idx, ME.message);
                amp5 = zeros(1, num_feeders);
                detected = -1;
                ratio_val = 0;
            end
            
            % --- 记录结果 ---
            is_correct = (detected == true_fault_line);
            results.compensation{case_idx}   = compensation_labels{i_comp};
            results.Rf(case_idx)             = Rf_val;
            results.alpha(case_idx)          = alpha_list(i_alpha);
            results.detected_line(case_idx)  = detected;
            results.is_correct(case_idx)     = is_correct;
            results.amp5_values(case_idx, :) = amp5;
            results.ratio(case_idx)          = ratio_val;
            
            % --- 进度显示 ---
            status_str = '✓';
            if ~is_correct, status_str = '✗'; end
            fprintf('  [%3d/%d] %s | Rf=%5.0fΩ | α=%3d° | L=%.4fH | 检测=馈线%d %s\n', ...
                case_idx, total_cases, compensation_labels{i_comp}, ...
                Rf_val, alpha_list(i_alpha), L_val, detected, status_str);
        end
    end
end

elapsed = toc;
fprintf('\n仿真完成，总耗时: %.1f 秒 (平均 %.1f 秒/工况)\n', elapsed, elapsed/total_cases);

%% ======================== 统计分析 ========================

fprintf('\n========================================\n');
fprintf('  五次谐波法选线准确率统计\n');
fprintf('========================================\n');

% --- 总体准确率 ---
total_correct = sum(results.is_correct);
total_accuracy = total_correct / total_cases * 100;
fprintf('\n【总体准确率】: %d/%d = %.1f%%\n', total_correct, total_cases, total_accuracy);

% --- 按故障电阻分类 ---
fprintf('\n--- 按故障电阻分类 ---\n');
for k = 1:length(Rf_list)
    mask = (results.Rf == Rf_list(k));
    acc = sum(results.is_correct(mask)) / sum(mask) * 100;
    fprintf('  Rf = %5.0f Ω : %.1f%% (%d/%d)\n', Rf_list(k), acc, sum(results.is_correct(mask)), sum(mask));
end

% --- 按故障初相角分类 ---
fprintf('\n--- 按故障初相角分类 ---\n');
for k = 1:length(alpha_list)
    mask = (results.alpha == alpha_list(k));
    acc = sum(results.is_correct(mask)) / sum(mask) * 100;
    fprintf('  α = %3d° : %.1f%% (%d/%d)\n', alpha_list(k), acc, sum(results.is_correct(mask)), sum(mask));
end

% --- 按补偿度分类 ---
fprintf('\n--- 按消弧线圈补偿度分类 ---\n');
for k = 1:length(compensation_labels)
    mask = strcmp(results.compensation, compensation_labels{k});
    acc = sum(results.is_correct(mask)) / sum(mask) * 100;
    fprintf('  %s : %.1f%% (%d/%d)\n', compensation_labels{k}, acc, sum(results.is_correct(mask)), sum(mask));
end

%% ======================== 生成结果表格 ========================

result_table = table(results.compensation, results.Rf, results.alpha, ...
    results.detected_line, results.is_correct, results.ratio, ...
    results.amp5_values(:,1), results.amp5_values(:,2), ...
    results.amp5_values(:,3), results.amp5_values(:,4), ...
    'VariableNames', {'补偿状态', 'Rf_Ohm', '初相角_deg', ...
    '检测馈线', '是否正确', '比率', ...
    'H5_馈线1', 'H5_馈线2', 'H5_馈线3', 'H5_馈线4'});

% 保存结果
save_path = fullfile(fileparts(which(mfilename)), 'Fifth_Harmonic_Results.mat');
save(save_path, 'result_table', 'results', 'total_accuracy');
fprintf('\n结果已保存至: %s\n', save_path);

%% ======================== 可视化：准确率热力图 ========================

figure('Name', '五次谐波法 — 准确率热力图', 'NumberTitle', 'off', ...
       'Position', [100, 100, 900, 400]);

for i_comp = 1:length(compensation_labels)
    subplot(1, 3, i_comp);
    acc_matrix = zeros(length(Rf_list), length(alpha_list));
    
    for i_rf = 1:length(Rf_list)
        for i_alpha = 1:length(alpha_list)
            mask = strcmp(results.compensation, compensation_labels{i_comp}) & ...
                   results.Rf == Rf_list(i_rf) & ...
                   results.alpha == alpha_list(i_alpha);
            acc_matrix(i_rf, i_alpha) = results.is_correct(mask);
        end
    end
    
    imagesc(acc_matrix);
    colormap(gca, [0.9 0.3 0.3; 0.3 0.8 0.3]);
    set(gca, 'XTick', 1:length(alpha_list), 'XTickLabel', alpha_list);
    set(gca, 'YTick', 1:length(Rf_list), 'YTickLabel', Rf_list);
    xlabel('故障初相角 (°)');
    ylabel('故障电阻 (Ω)');
    title(compensation_labels{i_comp});
    
    for r = 1:size(acc_matrix,1)
        for c = 1:size(acc_matrix,2)
            if acc_matrix(r,c)
                text(c, r, '✓', 'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', 'w');
            else
                text(c, r, '✗', 'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', 'w');
            end
        end
    end
end
sgtitle(sprintf('五次谐波法选线准确率热力图 (总准确率: %.1f%%)', total_accuracy), ...
    'FontSize', 14, 'FontWeight', 'bold');

fprintf('\n========== 五次谐波法准确性分析完成 ==========\n');
