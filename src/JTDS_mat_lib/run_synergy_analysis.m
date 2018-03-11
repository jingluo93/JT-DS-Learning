%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Evaluation of Learning Schemes for JTDS Models (including orientation) on Different Datasets     %%
%  Train and compare a series of JTDS models with different dimensionality                          %%   
%  reduction schemes and GMM model fitting                                                          %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear all; close all; clc;
do_plots  = 1;
data_path = '../../Data/mat/'; % <-Insert path to datasets folder here
choosen_dataset = 'pour'; % Options: 'back','fore','pour','pour_obst','foot','singularity';

%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Load and Process dataset %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%

switch choosen_dataset
    case 'back'
        demos_location = strcat(data_path, 'back_hand/data.mat');
        demo_ids = [2:11];
    case 'fore'
        demos_location = strcat(data_path,'fore_hand/data.mat');
        demo_ids = [1:11];
    case 'pour' 
        demos_location = strcat(data_path,'pour_no_obst/data.mat');
        demo_ids = [1 2 3 5 6 7 8 9 10];
    case 'pour_obst'
        demos_location = strcat(data_path,'pour_obst/data.mat');
        demo_ids = [1:10];
    case 'pour_obst_2'
        demos_location = strcat(data_path,'pour_obst_2/data.mat');
        demo_ids = [1:7];                
    case 'foot'        % This dataset was recorded at 50 Hz! thinning_ratio = 1 or 2
        demos_location = strcat(data_path,'foot/data.mat');
        demo_ids = [1:8];                
    case 'singularity'   
        demos_location = strcat(data_path,'singularity/data.mat');
        demo_ids = [1:10];  
        fprintf('Loading demonstrations from %s \n', demos_location);
        load(demos_location)
end

if ~strcmp(choosen_dataset,'singularity')
    fprintf('Loading demonstrations from %s \n', demos_location);
    [Qs_, Ts_] = ImportDemonstrations(demos_location);
end
% If the data is very dense, initializing the semidefinite program may take
% a long time. In this case, it may help to thin down the number of
% demonstrated points (by varying "thinning_ratio", so long as there are still sufficient points to
% satisfactorily reconstruct the shape of the trajectory.
% In the KUKA case, we get 500 datapoints per second, so we recommend shrinking the data density considerably
thinning_ratio = 20; % Same as demonstrations recorded at 10->50Hz, 20->25Hz
Qs = []; Ts= [];
for i = 1:length(demo_ids)
    Qs{i,1} = Qs_{demo_ids(i)}(:, 1:thinning_ratio:end);
    Ts{i,1} = Ts_{demo_ids(i)}(:, 1:thinning_ratio:end);
end

% Plot Full Set of Demonstrations per DOF
if do_plots
    figure('Color',[1 1 1])    
    Data_ = [];
    qdim = size(Qs{1},1);
    for dof=1:7
        subplot(qdim,1,dof)
        for i=1:length(Qs)
            data = Qs{i};
            data_dof = data(dof,:);
            plot(data_dof,'-.'); hold on;
        end
        grid on;
        title(sprintf('Raw Demonstrations for $q_%d$',dof), 'Interpreter', 'LaTex', 'Fontsize', 15)
        xlabel('Time (samples)','Interpreter', 'LaTex', 'Fontsize', 15)
        ylabel('Angle (rad)','Interpreter', 'LaTex', 'Fontsize', 15)
    end
end
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%    Train a JTDS model on the current dataset   %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Choose Lower-Dimensional Mapping Technique
mapping = {'PCA'}; % 'None', 'PCA', 'KPCA'

%%% Learning options %%%
options = [];
options.orientation_flag = 1;
options.tol_cutting = 0.1;

%%% Dim-Red options %%%
options.explained_variance_threshold = .95;
% If choosen mapping is K-PCA you need to choose the kernel width
% options.kpca_sigma = mean_D/sqrt(2);

%%% GMM options %%%
options.GMM_sigma_type = 'full'; % Can be either 'full' or 'diagonal'
options.GMM_maximize_BIC = true;
options.max_gaussians = 10;
options.plot_BIC = 0; 

% Optimization options 
options.learn_with_bounds = false;
options.verbose = true;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% DH parameters for the KUKA LWR 4+ robot %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dimq = 7;
A = [0 0 0 0 0 0 0.05];
Alpha = pi/2*[1 -1 -1 1 1 -1 0];
D = [.34 0 .4 0 .4 0 .279];
Qmin = 2*pi/180*[-85, -90, -100, -110, -140, -90, -120];
Qmax = 2*pi/180*[85, 90, 100, 110, 140, 90, 120];
% Create a model of the robot
robot = initialize_robot(A,D,Alpha,Qmin,Qmax);    
% Create a model plant for the robot's motor controller
robotplant = RobotPlant(robot, 'end_trans');

%%% Pre-process Data %%%
[Data_train, ~] = preprocess_demos_jtds(robotplant, Qs, Ts, options.tol_cutting,options.orientation_flag);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%       Learn JTDS variants for current fold      %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mapping_name = mapping{1};
fprintf('Training JTDS generator using %s mapping...\n', mapping_name);
options.latent_mapping_type = mapping_name;

% Run JTDS Solver function
[Priors, Mu, Sigma, As, latent_mapping] = JTDS_Solver_v2(Data_train, robotplant, options);
K = length(Priors);

if strcmp('PCA',latent_mapping.name)
    pca_dim = length(latent_mapping.lambda);
end

% Generate Trajectories from Learnt JTDS
motion_generator = MotionGenerator(robotplant, Mu, Sigma, Priors, As, latent_mapping);

% Compute RMSE on training data
rmse_train = mean(trajectory_error(motion_generator, Data_train(1:dimq, :), Data_train(dimq+1:2*dimq, :), Data_train(2*dimq+1:end, :),options.orientation_flag));
fprintf('Using %s mapping, got prediction RMSE on training: %d \n', mapping_name, rmse_train);

