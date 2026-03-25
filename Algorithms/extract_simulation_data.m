function [time_axis, i1, i2, i3, i4, u0] = extract_simulation_data(out)
% EXTRACT_SIMULATION_DATA 统一提取 Simulink 仿真数据
%   自动兼容 Timeseries / Structure / Array 三种输出格式
%   输入:  out - Simulink 仿真输出对象 (sim函数的返回值)
%   输出:  time_axis - 时间轴
%          i1~i4    - 四条馈线的零序电流数据
%          u0       - 零序电压数据 (如存在)

    % 提取电流数据
    if isa(out.simout1, 'timeseries')
        time_axis = out.simout1.Time;
        i1 = out.simout1.Data; i2 = out.simout2.Data;
        i3 = out.simout3.Data; i4 = out.simout4.Data;
    elseif isstruct(out.simout1)
        time_axis = out.simout1.time;
        i1 = out.simout1.signals.values; i2 = out.simout2.signals.values;
        i3 = out.simout3.signals.values; i4 = out.simout4.signals.values;
    else
        time_axis = out.tout;
        i1 = out.simout1; i2 = out.simout2;
        i3 = out.simout3; i4 = out.simout4;
    end

    % 提取零序电压数据 (比相法需要)
    u0 = [];
    try
        if isa(out.simout1, 'timeseries')
            u0 = out.simouv.Data;
        elseif isstruct(out.simout1)
            u0 = out.simouv.signals.values;
        else
            u0 = out.simouv;
        end
    catch
        % 如果模型中不存在 simouv，返回空数组
    end
end
