clc
clear all

%Load system
sys = SMD();
nx = sys.nx;
nu = sys.nu;
x0 = zeros(sys.nx,1);
x0(1) = 10;
Ts = 0.01;

%Number of episodes
epsds = 10000;

%Duration per episode
N = 500;

%Initial feedback gain U
U = -0.1*ones(1,nx);

%LQR costs
E= eye(nx)*10;
F = eye(nu)*0.01;

%Procedure
%For LQR, Q(x_t,u_t) = r(x_t,u_t)  + gamma*Q(x_(t+1),u_(t+1))
%Following usual steps, first do policy iteration to find how good U is
%Then do U = eps-greedy(Q)
%For LQR, Q(x_t,u_t) = [x_t; u_t]'*[H11 H12; H21 H22]*[x_t; u_t] - H is an
%unknown matrix, dependedent on system
%FOr LQR, r(x_t,u_t) = x_t'*E*x_t + u_t'*F*u_t - Known value
%So we can assemble all r's and in an LS sense, find H.

%Compute final optimal result for the SMD system--------------------------
M = sys.M;
c = sys.c;
K = sys.K;
A = [0 1; -K/M -c/M];
B = [0;1/M];
Ad = eye(nx)+A*Ts;
Bd = B*Ts;
[K,S,e] = lqr(A,B,E,F,0);
x = [10;0];
for i=2:N
    x = [x, (Ad-Bd*K)*x(:,end)];
end
figure('units','normalized','outerposition',[0 0 1 1])
subplot(2,2,2)
plot(x(1,:),':','LineWidth',2)
title('Position')
grid on
hold on
subplot(2,2,4)
plot(x(2,:),':','LineWidth',2)
title('Velocity')
grid on
hold on
subplot(2,2,1)
plot(-K*x,':','LineWidth',2)
title('Force In')
grid on
hold on
subplot(2,2,3)
title('LQ cost')
xlabel('Episode')
grid on
hold on
%-------------------------------------------------------------------------------------
feature = @(x,u)[x(1)^2; x(2)^2; x(1)*x(2); x(1)*u; x(2)*u; u^2];
W = ones(6,1);

%Define optimizer object
H = sdpvar(nx+nu,nx+nu);
x = sdpvar(nx,N-1);
u = sdpvar(nu,N-1);
cost = sdpvar(1,N-1);
prob = sdpvar(1,N-1);
f= 0 ;
    for i=1:N-1
        Q_value = [x(:,i)' u(:,i)']*H*[x(:,i); u(:,i)];
        f =f + prob(i)*(cost(i)-Q_value)^2;
    end
H_optim = optimizer([],f,[],{x,u,prob,cost},H);

%RL parameters
gamma = 1.0;
H = ones(nx+nu,nx+nu);
alpha = 1e-10;
noise = 5.0;

%Perform experiments and improvement
for eps = 1:epsds
    dW = zeros(size(W));
    %Calculate FB gain from H matrix
    H22 = H(nx+1:end,nx+1:end);
    H21 = H(nx+1:end,1:nu+1);
    U = -inv(H22)*H21
    %Store vectors
    x_vec{eps} = x0;
    u_vec{eps} = U*x0;
    cost_LQR{eps} = 0;
    for i=2:N
        %Propogate state
        x_vec{eps} = [x_vec{eps}, state_next(sys,x_vec{eps}(:,end),u_vec{eps}(:,end),Ts)];
        u_vec{eps} = [u_vec{eps}, U*x_vec{eps}(:,end)+noise*randn(nu)];
        %Calculate net cost
        cost_LQR{eps} = cost_LQR{eps}+ [x_vec{eps}(:,i)' u_vec{eps}(:,i)']*[E zeros(nx,nu); zeros(nu,nx) F]*[x_vec{eps}(:,i); u_vec{eps}(:,i)];
    end
    %Accumulate value gradient in an MC fashion
    %For stage i, recurse over all future states - Every visit MC
    distance = 0;
    for i=1:N-1
        cost(i) = 0;
        prob(i) = 0;
        for j=i:N
            stage_cost =  [x_vec{eps}(:,j)' u_vec{eps}(:,j)']*[E zeros(nx,nu); zeros(nu,nx) F]*[x_vec{eps}(:,j); u_vec{eps}(:,j)];
            cost(i) = cost(i) - (gamma^(j-1))*stage_cost;
            %Make distribution based on tile coading in [ {x},{u}] space
            distance_vector = [x_vec{eps}(:,i);u_vec{eps}(:,i)]-[x_vec{eps}(:,j);u_vec{eps}(:,j)];
            if sqrt(distance_vector'*distance_vector)<=distance
                prob(i) = prob(i)+1;
            end
        end
        prob(i) = prob(i)/(N-1);
        prob(i) = 1;
    end
    gd_iters = 1000;
    for gd = 1:gd_iters
        dH = zeros(size(H));
        for i=1:N-1
            %Calculate gradient
            %dH = dH+2*([x_vec{eps}(:,i);u_vec{eps}(:,i)]'*H*[x_vec{eps}(:,i);u_vec{eps}(:,i)]-cost(i))*[x_vec{eps}(:,i);u_vec{eps}(:,i)]*[x_vec{eps}(:,i);u_vec{eps}(:,i)]';
        end
        %H = H - alpha*dH ; 
    end
    net_error = 0;
    for i=1:N-1
        net_error = net_error + (cost(i)-[x_vec{eps}(:,i);u_vec{eps}(:,i)]'*H*[x_vec{eps}(:,i);u_vec{eps}(:,i)])^2;
    end
    net_error
    %Solve optmization problem
    H = H_optim(x_vec{eps}(:,1:N-1),u_vec{eps}(:,1:N-1),prob,cost);
    H = value(H);
    %Plotting
    subplot(2,2,2)
    plot(x_vec{eps}(1,:))
    hold on
    subplot(2,2,4)
    plot(x_vec{eps}(2,:))
    hold on
    subplot(2,2,1)
    plot(u_vec{eps}(1,:))
    hold on
    if eps>1
        subplot(2,2,3)
        line([eps-1,eps],[cost_LQR{eps-1},cost_LQR{eps}])
        hold on
    end
    pause(0.001)
end