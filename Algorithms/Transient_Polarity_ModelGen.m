% =========================================================================
% 配电网单相接地故障仿真模型 - 基础框架生成脚本
% =========================================================================

modelName = 'GroundingFault_Model_AutoGen';

% 1. 创建并打开新模型
try
    new_system(modelName);
catch
    warning('模型已存在，正在覆盖...');
    close_system(modelName, 0);
    new_system(modelName);
end
open_system(modelName);

% 2. 载入必需的库
load_system('powerlib');
load_system('simulink');

% -------------------------------------------------------------------------
% 模块添加与布局规划 (格式：[左, 上, 右, 下])
% -------------------------------------------------------------------------

% --- 系统与环境 ---
add_block('powerlib/powergui', [modelName, '/powergui'], 'Position', [750, 30, 820, 70]);
set_param([modelName, '/powergui'], 'SimulationMode', 'Discrete');

% --- 主电源侧 ---
% 三相交流电源
add_block('powerlib/Electrical Sources/Three-Phase Source', [modelName, '/Grid_Source'], 'Position', [50, 150, 110, 210]);
% 三相变压器 (Two Windings)
add_block('powerlib/Elements/Three-Phase Transformer (Two Windings)', [modelName, '/Main_Transformer'], 'Position', [200, 145, 260, 215]);
% 中性点接地电感 (消弧线圈/接地电阻)
add_block('powerlib/Elements/Series RLC Branch', [modelName, '/Neutral_Inductor'], 'Position', [120, 280, 140, 330]);
set_param([modelName, '/Neutral_Inductor'], 'BranchType', 'L'); % 设置为纯电感
set_param([modelName, '/Neutral_Inductor'], 'Orientation', 'down');
% 接地模块
add_block('powerlib/Elements/Ground', [modelName, '/Ground1'], 'Position', [120, 360, 140, 380]);

% --- 测量总线 ---
% 三相 V-I 测量
add_block('powerlib/Measurements/Three-Phase V-I Measurement', [modelName, '/V_I_Measurement'], 'Position', [320, 150, 370, 200]);

% --- 馈线与负载 (4条支路) ---
line_Y_start = 120;
spacing_Y = 100;
for i = 1:4
    % 线路 (PI 型)
    line_name = sprintf('/Line_Feeder%d', i);
    add_block('powerlib/Elements/Three-Phase PI Section Line', [modelName, line_name], ...
        'Position', [650, line_Y_start + (i-1)*spacing_Y, 730, line_Y_start + (i-1)*spacing_Y + 40]);
    
    % 电流测量 (零序电流提取用)
    meas_name = sprintf('/I_Meas_Line%d', i);
    add_block('powerlib/Measurements/Three-Phase V-I Measurement', [modelName, meas_name], ...
        'Position', [550, line_Y_start + (i-1)*spacing_Y, 600, line_Y_start + (i-1)*spacing_Y + 40]);
    set_param([modelName, meas_name], 'VoltageMeasurement', 'no'); % 仅测量电流
    
    % 负载
    load_name = sprintf('/Load%d', i);
    add_block('powerlib/Elements/Three-Phase Series RLC Load', [modelName, load_name], ...
        'Position', [850, line_Y_start + (i-1)*spacing_Y, 900, line_Y_start + (i-1)*spacing_Y + 50]);
end

% --- 故障模块 ---
% 三相故障模块 (挂在第一条线路上)
add_block('powerlib/Elements/Three-Phase Fault', [modelName, '/Grounding_Fault'], 'Position', [760, 20, 810, 70]);

% --- 信号处理与测量逻辑 (根据图示大致还原) ---
% 生成所需的 Math 运算模块，用于零序电压计算、乘法器等
add_block('simulink/Math Operations/Sum', [modelName, '/Sum_Voltage'], 'Position', [300, 280, 330, 310]);
set_param([modelName, '/Sum_Voltage'], 'Inputs', '+++'); % 3输入加法器，模拟 Ua+Ub+Uc = 3U0
add_block('simulink/Math Operations/Gain', [modelName, '/Gain_3U0'], 'Position', [360, 280, 390, 310]);
set_param([modelName, '/Gain_3U0'], 'Gain', '1/3'); % 提取 U0

% 添加 To Workspace 模块记录数据
workspace_vars = {'simout1', 'simout2', 'simout3', 'simout4', 'simout_u', 'mu'};
pos_x = 450; pos_y = 350;
for i = 1:length(workspace_vars)
    add_block('simulink/Sinks/To Workspace', [modelName, '/', workspace_vars{i}], ...
        'Position', [pos_x, pos_y + (i-1)*60, pos_x+60, pos_y + (i-1)*60 + 30]);
    set_param([modelName, '/', workspace_vars{i}], 'VariableName', workspace_vars{i});
end

% 添加 Goto / From 标签 (用于信号传递，避免线太乱)
tags = {'A', 'B', 'C', 'D'};
for i = 1:4
    add_block('simulink/Signal Routing/Goto', [modelName, '/Goto_', tags{i}], ...
        'Position', [500, 350 + (i-1)*50, 540, 350 + (i-1)*50 + 30]);
    set_param([modelName, '/Goto_', tags{i}], 'GotoTag', tags{i});
    
    add_block('simulink/Signal Routing/From', [modelName, '/From_', tags{i}], ...
        'Position', [200, 450 + (i-1)*50, 240, 450 + (i-1)*50 + 30]);
    set_param([modelName, '/From_', tags{i}], 'GotoTag', tags{i});
end

% 添加 Mux 模块合并波形
add_block('simulink/Signal Routing/Mux', [modelName, '/Mux_Output'], 'Position', [300, 450, 305, 630]);
set_param([modelName, '/Mux_Output'], 'Inputs', '4');
add_block('simulink/Sinks/Scope', [modelName, '/Scope_Main'], 'Position', [350, 520, 380, 560]);

% 整理完毕提示
disp('---------------------------------------------------');
disp('✅ 模型框架和元件已全部生成并排版完毕！');
disp('下一步你需要：');
disp('1. 连线：将电力端口 (黑色的方块引脚) 用线连接起来。');
disp('2. 参数：双击 Transformer、PI Line、Load 设置正确的阻抗和容量。');
disp('3. 逻辑：把信号测量的线连到运算模块上 (3U0, 3I0 计算)。');
disp('---------------------------------------------------');