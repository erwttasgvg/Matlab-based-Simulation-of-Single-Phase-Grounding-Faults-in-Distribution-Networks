% =========================================================================
% 脚本名称：暂态首半波极性比较法 — 准确性批量测试
% 文件名：  Transient_Polarity_Accuracy_Analysis.m
% 适用模型：Distribution_Fault_Model.slx
% -------------------------------------------------------------------------
% 功能说明：
%   自动遍历多种故障电阻、故障初相角、消弧线圈补偿度的组合工况，
%   对每种工况运行仿真并执行暂态极性法选线判据，统计算法的选线准确率。
%
% 核心原理：
%   故障发生瞬间，故障馈线上的对地电容通过故障点"放电"，健全馈线上的
%   电容通过故障点"充电"，两者暂态零序电流方向相反。
%   判据：在故障后极短时间窗口内，首半波极性与多数馈线相反者 = 故障线。
%   暂态分量频率远高于工频，消弧线圈对其几乎无阻碍。
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

% --- 暂态极性法参数 ---
transient_window = 0.002;  % 暂态窗口持续时间 (s): 故障后 2ms
noise_threshold = 0.01;    % 最小有效电流阈值 (A)，滤除噪声
fs = 20000;                % 采样频率 (Hz)

% --- 结果存储 ---
total_cases = length(L_coil_list) * length(Rf_list) * length(alpha_list);
results = struct();
results.compensation = cell(total_cases, 1);
results.Rf = zeros(total_cases, 1);
results.alpha = zeros(total_cases, 1);
results.detected_line = zeros(total_cases, 1);
results.is_correct = false(total_cases, 1);
results.peak_values = zeros(total_cases, num_feeders);
results.detection_method = cell(total_cases, 1);  % 极性法 or 备用幅值法

%% ======================== 加载模型 ========================

fprintf('========================================\n');
fprintf('  暂态极性法准确性批量测试 开始\n');
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
                
                % --- 截取暂态窗口 ---
                win_end = t_fault + transient_window;
                idx = (time_axis >= t_fault & time_axis <= win_end);
                
                i1_trans = i1(idx);
                i2_trans = i2(idx);
                i3_trans = i3(idx);
                i4_trans = i4(idx);
                
                % --- 提取首半波峰值（绝对值最大点的带符号值）---
                peaks = zeros(1, num_feeders);
                data_segs = {i1_trans, i2_trans, i3_trans, i4_trans};
                for k = 1:num_feeders
                    [~, loc] = max(abs(data_segs{k}));
                    peaks(k) = data_segs{k}(loc);
                end
                
                % --- 噪声过滤 ---
                valid_peaks = peaks;
                valid_peaks(abs(valid_peaks) < noise_threshold) = 0;
                
                % --- 极性比较选线逻辑 ---
                pos_count = sum(valid_peaks > 0);
                neg_count = sum(valid_peaks < 0);
                
                detect_method = '';
                if pos_count == (num_feeders - 1) && neg_count == 1
                    % (n-1) 正 + 1 负 → 负极性为故障线
                    [~, detected] = min(valid_peaks);
                    detect_method = '极性法(多正一负)';
                elseif neg_count == (num_feeders - 1) && pos_count == 1
                    % (n-1) 负 + 1 正 → 正极性为故障线
                    [~, detected] = max(valid_peaks);
                    detect_method = '极性法(多负一正)';
                else
                    % 非典型模式 → 退化为暂态幅值比较
                    [~, detected] = max(abs(valid_peaks));
                    detect_method = '备用幅值法';
                    if all(valid_peaks == 0)
                        detected = 0;
                        detect_method = '信号过弱';
                    end
                end
                
            catch ME
                fprintf('  [错误] 工况 %d: %s\n', case_idx, ME.message);
                peaks = zeros(1, num_feeders);
                detected = -1;
                detect_method = '仿真错误';
            end
            
            % --- 记录结果 ---
            is_correct = (detected == true_fault_line);
            results.compensation{case_idx}      = compensation_labels{i_comp};
            results.Rf(case_idx)                = Rf_val;
            results.alpha(case_idx)             = alpha_list(i_alpha);
            results.detected_line(case_idx)     = detected;
            results.is_correct(case_idx)        = is_correct;
            results.peak_values(case_idx, :)    = peaks;
            results.detection_method{case_idx}  = detect_method;
            
            % --- 进度显示 ---
            status_str = '✓';
            if ~is_correct, status_str = '✗'; end
            fprintf('  [%3d/%d] %s | Rf=%5.0fΩ | α=%3d° | L=%.4fH | %s → 馈线%d %s\n', ...
                case_idx, total_cases, compensation_labels{i_comp}, ...
                Rf_val, alpha_list(i_alpha), L_val, detect_method, detected, status_str);
        end
    end
end

elapsed = toc;
fprintf('\n仿真完成，总耗时: %.1f 秒 (平均 %.1f 秒/工况)\n', elapsed, elapsed/total_cases);

%% ======================== 统计分析 ========================

fprintf('\n========================================\n');
fprintf('  暂态极性法选线准确率统计\n');
fprintf('========================================\n');

% --- 总体准确率 ---
total_correct = sum(results.is_correct);
total_accuracy = total_correct / total_cases * 100;
fprintf('\n【总体准确率】: %d/%d = %.1f%%\n', total_correct, total_cases, total_accuracy);

% --- 按检测方法分类 ---
fprintf('\n--- 按检测方法分类 ---\n');
unique_methods = unique(results.detection_method);
for k = 1:length(unique_methods)
    mask = strcmp(results.detection_method, unique_methods{k});
    n_total = sum(mask);
    n_correct = sum(results.is_correct(mask));
    fprintf('  %s : %.1f%% (%d/%d)\n', unique_methods{k}, n_correct/n_total*100, n_correct, n_total);
end

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
    results.detected_line, results.is_correct, results.detection_method, ...
    results.peak_values(:,1), results.peak_values(:,2), ...
    results.peak_values(:,3), results.peak_values(:,4), ...
    'VariableNames', {'补偿状态', 'Rf_Ohm', '初相角_deg', ...
    '检测馈线', '是否正确', '检测方法', ...
    'Peak_馈线1', 'Peak_馈线2', 'Peak_馈线3', 'Peak_馈线4'});

% 保存结果
save_path = fullfile(fileparts(which(mfilename)), 'Transient_Polarity_Results.mat');
save(save_path, 'result_table', 'results', 'total_accuracy');
fprintf('\n结果已保存至: %s\n', save_path);

%% ======================== 可视化：准确率热力图 ========================

figure('Name', '暂态极性法 — 准确率热力图', 'NumberTitle', 'off', ...
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
sgtitle(sprintf('暂态极性法选线准确率热力图 (总准确率: %.1f%%)', total_accuracy), ...
    'FontSize', 14, 'FontWeight', 'bold');

fprintf('\n========== 暂态极性法准确性分析完成 ==========\n');
