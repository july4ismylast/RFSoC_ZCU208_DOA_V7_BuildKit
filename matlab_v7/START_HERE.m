%% START_HERE - Verify, build, and run the complete Simulink homing model.
close all; clearvars; clc;
rehash path;

fprintf('\nSTEP 1/3: Verifying MATLAB R2024a classes and DOA direction...\n');
verify_r2024a_setup;
clear objects;

fprintf('\nSTEP 2/3: Building DOA_3D_Homing.slx...\n');
build_3d_doa_simulink;

fprintf('\nSTEP 3/3: Running the moving-target homing simulation...\n');
simulationOutput=sim('DOA_3D_Homing');
plot_simulink_results(simulationOutput);
