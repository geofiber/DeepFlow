%% sensitivitiesModel2D - analyse sensitivity capabilities 
clear all;
LASTN = maxNumCompThreads(4);
mrstModule add ad-core ad-blackoil ad-props optimization spe10 mrst-gui

% Setup model -> grid, rock, schedule, fluid etc
setupModel
%% Reset fluid to include scaling:
% $s_w -> \frac{s_w-swcr}{swu-swcr}$
% $s_o -> \frac{s_o-sowcr}{1-swl-sowcr}$
fluid = initSimpleScaledADIFluid('mu',    [.3, 5, 0]*centi*poise, ...
                                 'rho',   [1000, 700, 0]*kilogram/meter^3, ...
                                 'n',     [2, 2, 0], ...
                                 'swl',   0.10*ones(G.cells.num,1), ...
                                 'swcr',  0.15*ones(G.cells.num,1), ...
                                 'sowcr', 0.12*ones(G.cells.num,1), ...
                                 'swu',   0.90*ones(G.cells.num,1));
                                 
inputArg = getenv('case_name');                       
% Create model-object of class TwoPhaseOilWaterModel  
model_ref  = load(join(['utils/', inputArg, '/model_ref.mat']));%                   
model_ref = model_ref.model_ref;

% Set initial state and run simulation:
state0 = initResSol(G, 200*barsa, [.15, .85]);

% Set up a perturbed model with different pv and perm:
rock1 = gethalfcircle();

model = TwoPhaseOilWaterModel(G, rock1, fluid);

% load ref model
ws_ref = load(join(['utils/', inputArg, '/ws_ref.mat']));
ws_ref = ws_ref.ws_ref;

states_ref = load(join(['utils/', inputArg, '/states_ref.mat']));
states_ref = states_ref.states_ref;

r_ref = load(join(['utils/', inputArg, '/r_ref.mat']));
r_ref = r_ref.r_ref;

% run model
[ws, states, r] = simulateScheduleAD(state0, model, schedule);

%% setup misfit-function and run adjoint to get parameter sensitivities
% setup weights for matching function, empty weight uses default (will 
% produce function value of ~O(1) for 100% misfit). Only match rates in this example: 
weighting =  {'WaterRateWeight',     [], ...
              'OilRateWeight',       [] , ...
              'BHPWeight',           []};
   
% compute misfit function value (first each summand corresonding to each time-step)
misfitVals = matchObservedOW(G, ws, schedule, ws_ref, weighting{:});

% sum values to obtiain scalar objective 
misfitVal = sum(vertcat(misfitVals{:}));
fprintf('Current misfit value: %6.4e\n', misfitVal)

% setup (per time step) mismatch function handle for passing on to adjoint sim
objh = @(tstep)matchObservedOW(G, ws, schedule, ws_ref, 'computePartials', true, 'tstep', tstep, weighting{:});

% run adjoint to compute sensitivities of misfit wrt params
% choose parameters, get multiplier sensitivities except for endpoints
params      = {'porevolume', 'permeability'};
paramTypes  = {'multiplier', 'multiplier'};

sens = computeSensitivitiesAdjointAD(state0, states, model, schedule, objh, ...
                                     'Parameters'    , params, ...
                                     'ParameterTypes', paramTypes);

save('utils/synthetic/grad.mat', 'sens');
save('utils/synthetic/misfit.mat', 'misfitVal');
save('utils/synthetic/ws.mat', 'ws');
