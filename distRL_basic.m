clc
clear all

%Dynamics---------------------------------
a1 = 0.8;
a2 = 0.5;
b1 = 1;
b2 = 1;

%Initialziation------------------------------
%Sys 1
H_1 = 0.01*ones(2);
H_12 = 0.001*ones(2);
x1_start = 10;
%Sys 2
H_2 = 0.01*ones(2);
H_21 = 0.002*ones(2);
x2_start = 15;

%Get the greedy gains--------------------
% matrix_1 = [H_21(2,2)+H_12(2,2) 2*H_2(2,2);...
%                          2*H_1(2,2)  H_12(2,2)+H_21(2,2)];
% matrix_2 = -[H_12(1,2)+H_21(2,1) H_2(2,1)+H_2(1,2);...
%                            H_1(2,1)+H_1(1,2)   H_12(2,1)+H_21(1,2)];
% gains = inv(matrix_1)*matrix_2;
% gains = gains/100;
K_11 = -0.01;
K_12 = 0.01;
K_21 = 0.01;
K_22 = -0.01;

%Global cost params----------------------
E1 = 1; %Indiv weight
E2 = 0; %Combined weight
F = 10; %Input weight

%Sim params------------------------------
N_MC = 1;
N_sim = 50;

%Calculate ideal trajectories-------------
A = [a1 0; 0 a2];
B = [b1 0; 0 b2];
Q = [E1+E2 -E2; -E2 E1+E2];
R = [F 0; 0 F];
[K,S,~] = dlqr(A,B,Q,R,0);
x_sim = [x1_start;x2_start];
for j=2:N_sim
    u_sim(:,j-1) = -K*x_sim(:,j-1);
    x_sim(:,j) = A*x_sim(:,j-1)+B*u_sim(:,j-1);
end
%For verification, build H matrix
H = [Q+A'*S*A A'*S*B; B'*S*A F+B'*S*B];
%This is of the structure [x1 x2 u1 u2]
%Have to rearrrange to [x1 u1 x2 u2]
idx = [1 3 2 4];
H = H(idx,idx);
H11 = H(1:2,1:2);
H12 = H(1:2,3:4);
H21 = H(3:4,1:2);
H22 = H(3:4,3:4);
%Verify if costs correspond correctly
for j=1:N_sim-1
    cost1(j) = 0;
    cost2(j) = 0;
    for k=j:N_sim-1
        cost1(j) = cost1(j) + (E1+E2)*x_sim(1,k)^2 + F*u_sim(1,k)^2 - E2*x_sim(1,k)*x_sim(2,k);
        cost2(j) = cost2(j) + (E1+E2)*x_sim(2,k)^2 + F*u_sim(2,k)^2 - E2*x_sim(1,k)*x_sim(2,k);
    end
    cost1_calc(j) = [x_sim(1,j) u_sim(1,j)]*H11*[x_sim(1,j);u_sim(1,j)]+[x_sim(1,j) u_sim(1,j)]*H12*[x_sim(2,j);u_sim(2,j)];
    cost2_calc(j) = [x_sim(2,j) u_sim(2,j)]*H22*[x_sim(2,j);u_sim(2,j)]+[x_sim(2,j) u_sim(2,j)]*H21*[x_sim(1,j);u_sim(1,j)];
end
    

% % %Build optimizer object for faster sim
% H_a = sdpvar(2,2);
% H_ab = sdpvar(2,2);
% cost_a = sdpvar(1,N_sim-1);
% x_a = sdpvar(1,N_sim-1);
% x_b = sdpvar(1,N_sim-1);
% u_a = sdpvar(1,N_sim-1);
% u_b = sdpvar(1,N_sim-1);
% f_a = 0;
% for j=1:N_sim-1
%     j
%     f_a = f_a+([x_a(j) u_a(j)]*H_a*[x_a(j);u_a(j)]+[x_a(j) u_a(j)]*H_ab*[x_b(j);u_b(j)]-cost_a(j))^2;
% end
% find_H = optimizer([],f_a,sdpsettings('solver','quadprog'),{x_a,x_b,u_a,u_b,cost_a},{H_a,H_ab});

%Simulate----------------------------------
figure
alpha_1 = [];
alpha_2 = [];
num_gd_iters = 50;
for i=1:N_MC
    x1_vec = x1_start;
    u1_vec = [];
    x2_vec = x2_start;
    u2_vec = [];
    %Do one MC run===============
    for j=2:N_sim
        %Calculate inputs through exchange
        u1_vec = [u1_vec K_11(end)*x1_vec(j-1)+K_12(end)*x2_vec(j-1)+0.0*randn(1)];
        u2_vec = [u2_vec K_22(end)*x2_vec(j-1)+K_21(end)*x1_vec(j-1)+0.0*randn(1)];
        %Simulate systems
        x1_vec(j) = a1*x1_vec(j-1)+b1*u1_vec(j-1);
        x2_vec(j) = a2*x2_vec(j-1)+b2*u2_vec(j-1);
    end
    %Compute cost till end===============
    for j=1:N_sim
        cost_1(j) = 0;
        cost_2(j) = 0;
        for k=j:N_sim-1
            cost_1(j) = cost_1(j) + x1_vec(k)'*(E1+E2)*x1_vec(k) + u1_vec(k)'*F*u1_vec(k) - x1_vec(k)'*E2*x2_vec(k);
            cost_2(j) = cost_2(j) + x2_vec(k)'*(E1+E2)*x2_vec(k) + u2_vec(k)'*F*u2_vec(k) - x2_vec(k)'*E2*x1_vec(k);
        end
    end
    %Compute H_1 and H12 matrices on system 1===============
    %System 1-------
    H1_vector = [H_1(1,1);H_1(1,2);H_1(2,1);H_1(2,2);H_12(1,1);H_12(1,2);H_12(2,1);H_12(2,2)];
    for gd_iters = 1:num_gd_iters
        %Calculate gradient at evaluated point
        dH1_sum = zeros(8,1);
        mat_1 = zeros(N_sim-1,8);
        for j=1:N_sim-1
            %For ease of notation
            mat_1(j,:) = [x1_vec(j)*x1_vec(j)' x1_vec(j)*u1_vec(j)' u1_vec(j)*x1_vec(j)' u1_vec(j)*u1_vec(j)' ...
                                     x1_vec(j)*x2_vec(j)' x1_vec(j)*u2_vec(j)' x2_vec(j)*u1_vec(j)' u1_vec(j)*u2_vec(j)'];
            %Enumerate gradient
            dH1_sum = dH1_sum+(mat_1(j,:)*H1_vector-cost_1(j))*mat_1(j,:)';
        end
        %Calculate optimal step size at the current point
        num = 0;
        den = 0;
        for j=1:N_sim-1
            vector = cost_1(j);
            num = num+ (vector*mat_1(j,:)*dH1_sum-mat_1(j,:)*H1_vector*mat_1(j,:)*dH1_sum);
            den = den + (mat_1(j,:)*dH1_sum)^2;
        end
        alpha_1 = [alpha_1 num/den];
        %Take a gradient step
        H1_vector = H1_vector+alpha_1(end)*dH1_sum;
    end
    H_1 = [H1_vector(1) H1_vector(2); H1_vector(3) H1_vector(4)];
    H_12 = [H1_vector(5) H1_vector(6); H1_vector(7) H1_vector(8)];
    
    %System 2-------
    H2_vector = [H_2(1,1);H_2(1,2);H_2(2,1);H_2(2,2);H_21(1,1);H_21(1,2);H_21(2,1);H_21(2,2)];
    for gd_iters = 1:num_gd_iters
        %Calculate gradient at evaluated point
        dH2_sum = zeros(8,1);
        mat_2 = zeros(N_sim-1,8);
        for j=1:N_sim-1
            %For ease of notation
            mat_2(j,:) = [x2_vec(j)*x2_vec(j)' x2_vec(j)*u2_vec(j)' u2_vec(j)*x2_vec(j)' u2_vec(j)*u2_vec(j)' ...
                                     x2_vec(j)*x1_vec(j)' x2_vec(j)*u1_vec(j)' u2_vec(j)*x1_vec(j)' u2_vec(j)*u1_vec(j)'];
            %Enumerate gradient
            dH2_sum = dH2_sum+(mat_2(j,:)*H2_vector-cost_2(j))*mat_2(j,:)';
        end
        %Calculate optimal step size at the current point
        num = 0;
        den = 0;
        for j=1:N_sim-1
            vector = cost_2(j);
            num = num+ (vector*mat_2(j,:)*dH2_sum-mat_2(j,:)*H2_vector*mat_2(j,:)*dH2_sum);
            den = den + (mat_2(j,:)*dH2_sum)^2;
        end
        alpha_2 = [alpha_2 num/den];
        %Take a gradient step
        H2_vector = H2_vector+alpha_2(end)*dH2_sum;
    end
    H_2 = [H2_vector(1) H2_vector(2); H2_vector(3) H2_vector(4)];
    H_21 = [H2_vector(5) H2_vector(6); H2_vector(7) H2_vector(8)];
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %     H_1_matrices = find_H{{x1_vec(1:end-1),x2_vec(1:end-1),u1_vec,u2_vec,cost_1(1:end-1)}};
    %     H_1 = H_1_matrices{1};
    %     H_12  = H_1_matrices{2};
    %     %Compute H_2 and H21 matrices on system 2===============
    %     H_2_matrices = find_H{{x2_vec(1:end-1),x1_vec(1:end-1),u2_vec,u1_vec,cost_2(1:end-1)}};
    %     H_2 = H_2_matrices{1};
    %     H_21  = H_2_matrices{2};
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    %Find greedy feedback gains based on these H matrices
    matrix_1 = [H_21(2,2)+H_12(2,2) 2*H_2(2,2);...
                            2*H_1(2,2)  H_12(2,2)+H_21(2,2)];
    matrix_2 = -[H_12(1,2)+H_21(2,1) H_2(2,1)+H_2(1,2);...
                              H_1(2,1)+H_1(1,2)   H_12(2,1)+H_21(1,2)];
    gains = inv(matrix_1)*matrix_2;
%     K_11 = [K_11 gains(1,1)];
%     K_12 = [K_12 gains(1,2)];
%     K_21 = [K_21 gains(2,1)];
%     K_22 = [K_22 gains(2,2)];
    
    %Plot to verify
    subplot(2,2,1)
    scatter(i,-K(1,1),'.','black')
    hold on
    scatter(i,K_11(end),'.','red')
    hold on
    subplot(2,2,2)
    scatter(i,-K(1,2),'.','black')
    hold on
    scatter(i,K_12(end),'.','red')
    hold on
    subplot(2,2,3)
    scatter(i,-K(2,1),'.','black')
    hold on
    scatter(i,K_21(end),'.','red')
    hold on
    subplot(2,2,4)
    scatter(i,-K(2,2),'.','black')
    hold on
    scatter(i,K_22(end),'.','red')
    hold on
     pause(0.001)
    
end

%Check if net cost matches the H
K_sim = [K_11 K_12; K_21 K_22];
x_verify = [x1_start; x2_start];
for j=2:N_sim
    u_verify(:,j-1) = K_sim*x_verify(:,j-1);
    x_verify(:,j) = A*x_verify(:,j-1) + B*u_verify(:,j-1);
end
%Calculate net costs
for j=1:N_sim-1
    cost_enum(j) = 0;
    for k=j:N_sim-1
        cost_enum(j) = cost_enum(j) + x_verify(:,k)'*Q*x_verify(:,k) + u_verify(:,k)'*R*u_verify(:,k);
    end
    cost_H(j) = [x_verify(1,j);u_verify(1,j);x_verify(2,j);u_verify(2,j)]'*[H_1 H_12; H_21 H_2]*[x_verify(1,j);u_verify(1,j);x_verify(2,j);u_verify(2,j)];
end

figure
plot(cost_H)
hold on
plot(cost_enum)
    
    