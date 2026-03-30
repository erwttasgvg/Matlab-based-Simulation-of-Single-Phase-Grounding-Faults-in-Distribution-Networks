% TYUT 电气工程：R2025a 鲁棒性连线脚本
clear; clc;
model_name = 'TYUT_EE_Final_Model';

if bdIsLoaded(model_name); close_system(model_name, 0); end
new_system(model_name); open_system(model_name);

% 1. 放置模块
add_block('powerlib/Electrical Sources/Three-Phase Source', [model_name '/Source'], 'Position', [50, 150, 150, 220]);
add_block('powerlib/Measurements/Three-Phase V-I Measurement', [model_name '/Measure'], 'Position', [250, 145, 350, 225]);
add_block('powerlib/Elements/Three-Phase Series RLC Load', [model_name '/Load'], 'Position', [500, 150, 600, 220]);
add_block('powerlib/Elements/Three-Phase Fault', [model_name '/Fault'], 'Position', [400, 300, 480, 360]);
add_block('powerlib/powergui', [model_name '/powergui'], 'Position', [50, 30, 120, 60]);
add_block('simulink/Sinks/Scope', [model_name '/Scope'], 'Position', [550, 50, 600, 100]);

% 2. 尝试配置参数 (如果报错则跳过，保证连线执行)
try
    set_param([model_name '/Source'], 'Voltage', '10e3', 'InternalConnection', 'Y');
    % R2025a 可能将 'yes' 改为了 'on'
    set_param([model_name '/Measure'], 'VoltageMeasurement', 'on'); 
    set_param([model_name '/Fault'], 'PhaseA', 'on', 'GroundFault', 'on', 'SwitchTimes', '[0.02]');
catch
    disp('部分参数配置在 R2025a 中略有差异，已跳过，请手动在界面调整。');
end

% 3. 强力连线逻辑 (即便参数报错，这段也一定会执行)
disp('>>> 正在拉设 A/B/C 三相强电电缆...');

% 电源 -> 测量仪
add_line(model_name, 'Source/RConn1', 'Measure/LConn1', 'autorouting', 'on');
add_line(model_name, 'Source/RConn2', 'Measure/LConn2', 'autorouting', 'on');
add_line(model_name, 'Source/RConn3', 'Measure/LConn3', 'autorouting', 'on');

% 测量仪 -> 负载
add_line(model_name, 'Measure/RConn1', 'Load/LConn1', 'autorouting', 'on');
add_line(model_name, 'Measure/RConn2', 'Load/LConn2', 'autorouting', 'on');
add_line(model_name, 'Measure/RConn3', 'Load/LConn3', 'autorouting', 'on');

% 将故障模块挂在 ABC 三线上 (并联)
add_line(model_name, 'Measure/RConn1', 'Fault/LConn1', 'autorouting', 'on');
add_line(model_name, 'Measure/RConn2', 'Fault/LConn2', 'autorouting', 'on');
add_line(model_name, 'Measure/RConn3', 'Fault/LConn3', 'autorouting', 'on');

% 测量信号 -> 示波器
try
    add_line(model_name, 'Measure/1', 'Scope/1', 'autorouting', 'on');
catch
    disp('信号线连接建议手动操作：从 Measure 的 v 端口连到 Scope。');
end

save_system(model_name);
disp('>>> 连线已完成！请检查 Simulink 窗口。');