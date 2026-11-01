%% RUN_SIMULINK_HOMING Build and run the complete Simulink demonstration.
close all; clearvars; clc;
rehash path;
build_3d_doa_simulink;
simulationOutput=sim('DOA_3D_Homing');
plot_simulink_results(simulationOutput);
