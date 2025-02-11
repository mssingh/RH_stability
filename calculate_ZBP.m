function [T,p,z,RH,Tm,gamma] = calculate_ZBP(z,pl,Tl,epsilon,PE,varargin)
%
% Calculate the temperature and relative humidity profiles
% between two levels zl and zm in the lower troposphere
% based on the zero-buoyancy plume model. 
%
% Inputs:
%
%    z       = height (m) of lower and upper levels or height vector
%              or vector of given height levels of length Nz
%
%    These variables can be any size (Tsize)
%
%    Tl      = temperature at lower level (K)
%    epsilon = entrainment rate           (m^-1)
%    PE      = precipitation efficiency   (0-1)
%
%    p       = pressure (Pa) of lower level (size = Tsize)
%              pressure (Pa) at each level  (size = [Tsize Nz])
%
%
% Outputs:
%
%    All outputs of size = [Tsize length(z)]
%
%    T       = temperature (K)
%    p       = pressure (Pa)
%    z       = height (m)
%    RH      = relative humidity (0-1)
%    Tm      = moist adiabat temperature (K)


%% Inputs %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
entrainment_type = 'const';
if nargin >= 6; entrainment_type = varargin{1}; end

%% Thermodynamics %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
c = atm.load_constants;


%% Initialise height vector %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Initialise height vector
if length(z) <= 2

   if length(z) ~=2; error('z should be a two element vector giving the lower and upper bound'); end
   zl = z(1);
   zm = z(2);
   
   % Set grid spacing to 50 m
   dz = 50;

   z = zl:dz:zm;
   if z(end) ~= zm; z(end+1) = zm; end

end



%% Check size of inputs %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Size of pressure and temperature arrays
pshape = size(pl);
Tshape = size(Tl);

% Remove leading singleton if required
if Tshape(1) ==1; Tshape = Tshape(2:end); end
if pshape(1) ==1; pshape = pshape(2:end); end

Nl = length(Tshape);
Nz = length(z);

% Parse the shape of the pressure array
if isequal(pshape,Tshape)

    % If pl is same size as Tl, pressure at lower level is given
    % Need to calculate pressure with height
    calc_pressure = 1;

else

    % If not, we are given pressure at all levels, 
    % and no need to calculate pressure
    calc_pressure = 0;
    
    % Check that pressure is of the right size
    if isequal(pshape,[Tshape Nz])

        % p is as we need it
        p = pl;
       
    elseif isequal(pshape,[Nz Tshape])

        % p is around the wrong way, but we can fix it
        p = permute(pl,[2:length(pshape) 1]);


    else
           % We have an error
           disp(['size(p)  = ' num2str(pshape)])
           disp(['size(T)  = ' num2str([Tshape Nz])])
           error('Size error') 
    end

end


% All other inputs should be the same size as Tl or scalars.
% Currently, we do not check for this



%% Prepare matrices %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Flatten the input variables 
Tl = Tl(:);
pl = pl(:);
epsilon = epsilon(:);
PE = PE(:);
   
[~,~,~,gammal] = calculate_ZBP_lapse_rate(Tl,pl,epsilon,PE);


% Initialise temperature, moist adiabat, pressure and RH vectors
T  = zeros([length(Tl) Nz]);
Tm = zeros([length(Tl) Nz]);
RH = zeros([length(Tl) Nz]);
gamma = zeros([length(Tl) Nz]);

if calc_pressure 
    p = zeros([length(Tl) Nz]);
    p(:,1) = pl; 
end


T(:,1) = Tl;
Tm(:,1) = Tl;


%% Integrate lapse rate equation %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% functions that give the lapse rate and moist-adiabatic lapse rate

    % Set the entrainment rate
    switch entrainment_type

        case 'const'

            function_dTpdz = @(z,Tp) [-calculate_ZBP_lapse_rate(Tp(:,1),exp(Tp(:,2)),epsilon,PE); -(c.g)./(c.Rd.*Tp(:,1))];
        case 'invz'

            function_dTpdz = @(z,Tp) [-calculate_ZBP_lapse_rate(Tp(:,1),exp(Tp(:,2)),epsilon.*1000./z,PE); -(c.g)./(c.Rd.*Tp(:,1))];

        case 'gamma'
        
            function_dTpdz = @(z,Tp) [-calculate_ZBP_lapse_rate_a(Tp(:,1),exp(Tp(:,2)),epsilon.*PE./gammal,PE); -(c.g)./(c.Rd.*Tp(:,1))];

        otherwise
            error('unknown entrainment type')

    end
    
function_dTpdz_adiabat = @(z,Tp) [-calculate_ZBP_lapse_rate(Tp(:,1),exp(Tp(:,2)),0,1); -(c.g)./(c.Rd.*Tp(:,1))];

for i = 1:length(z)

    % Set the entrainment rate
    switch entrainment_type

        case 'const'

            epsi = epsilon;
            % Get the relative humidity
            [~,~,RH(:,i),gamma(:,i)] = calculate_ZBP_lapse_rate(T(:,i),p(:,i),epsi,PE);

        case 'invz'

            epsi = epsilon.*1000./z(i);
            % Get the relative humidity
            [~,~,RH(:,i),gamma(:,i)] = calculate_ZBP_lapse_rate(T(:,i),p(:,i),epsi,PE);

        case 'gamma'
    
            % Get the relative humidity and gamma
            [~,~,RH(:,i),gamma(:,i)] = calculate_ZBP_lapse_rate_a(T(:,i),p(:,i),epsilon.*PE./gammal,PE);

        otherwise
            error('unknown entrainment type')

    end




    if i < length(z)
        
      % Set the step size
      dz = z(i+1)-z(i);

      % Solve for the temperature and pressure at level i+1
      Tp_in = cat(2,T(:,i),log(p(:,i)));
      [Tp_out,~] = ODE.rk_step(function_dTpdz,Tp_in,z(i),dz,'rk4');

      % Solve also for the moist adiabat
      Tp_in = cat(2,Tm(:,i),log(p(:,i)));   % Note that we use the regular pressure
      [Tpm_out,~] = ODE.rk_step(function_dTpdz_adiabat,Tp_in,z(i),dz,'rk4');

      % Set the variables at level i+1
      T(:,i+1) = Tp_out(:,1);
      Tm(:,i+1) = Tpm_out(:,1);
      if calc_pressure; p(:,i+1) = exp(Tp_out(:,2)); end



    
    end

  
end

% Make the arrays the shape we want
T  = permute(reshape(T,[Tshape Nz]),[Nl+1 1:Nl]);
Tm = permute(reshape(Tm,[Tshape Nz]),[Nl+1 1:Nl]);
p  = permute(reshape(p,[Tshape Nz]),[Nl+1 1:Nl]);
RH = permute(reshape(RH,[Tshape Nz]),[Nl+1 1:Nl]);






    
