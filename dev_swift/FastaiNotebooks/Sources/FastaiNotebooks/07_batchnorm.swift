/*
THIS FILE WAS AUTOGENERATED! DO NOT EDIT!
file to edit: 07_batchnorm.ipynb

*/
        
import Path
import TensorFlow
import Python

class Reference<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

protocol LearningPhaseDependent: Layer {
    associatedtype Input
    associatedtype Output
    
    var delegate: LayerDelegate<Output> { get set }
    @differentiable func forwardTraining(to input: Input) -> Output
    @differentiable func forwardInference(to input: Input) -> Output
}

extension LearningPhaseDependent {
    func forward(_ input: Input) -> Output {
        switch Context.local.learningPhase {
        case .training: return forwardTraining(to: input)
        case .inference: return forwardInference(to: input)
        }
    }

    @differentiating(forward)
    func gradForward(_ input: Input) ->
        (value: Output, pullback: (Self.Output.CotangentVector) ->
            (Self.CotangentVector, Self.Input.CotangentVector)) {
        switch Context.local.learningPhase {
        case .training:
            return valueWithPullback(at: input) { $0.forwardTraining(to: $1) }
        case .inference:
            return valueWithPullback(at: input) { $0.forwardInference(to: $1) }
        }
    }
    
    @differentiable
    public func call(_ input: Input) -> Output {
        let activation = forward(input)
        delegate.didProduceActivation(activation)
        return activation
    }
}

protocol Norm: Layer where Input == Tensor<Scalar>, Output == Tensor<Scalar>{
    associatedtype Scalar
    init(featureCount: Int, epsilon: Scalar)
}

public struct FABatchNorm<Scalar: TensorFlowFloatingPoint>: LearningPhaseDependent, Norm {
    // Configuration hyperparameters
    @noDerivative var momentum: Scalar
    @noDerivative var epsilon: Scalar
    // Running statistics
    @noDerivative let runningMean: Reference<Tensor<Scalar>>
    @noDerivative let runningVariance: Reference<Tensor<Scalar>>
    @noDerivative public var delegate: LayerDelegate<Output> = LayerDelegate()
    // Trainable parameters
    public var scale: Tensor<Scalar>
    public var offset: Tensor<Scalar>
    
    public init(featureCount: Int, momentum: Scalar, epsilon: Scalar = 1e-5) {
        self.momentum = momentum
        self.epsilon = epsilon
        self.scale = Tensor(ones: [featureCount])
        self.offset = Tensor(zeros: [featureCount])
        self.runningMean = Reference(Tensor(0))
        self.runningVariance = Reference(Tensor(1))
    }
    
    public init(featureCount: Int, epsilon: Scalar = 1e-5) {
        self.init(featureCount: featureCount, momentum: 0.9, epsilon: epsilon)
    }

    @differentiable
    public func forwardTraining(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        let mean = input.mean(alongAxes: [0, 1, 2])
        let variance = input.variance(alongAxes: [0, 1, 2])
        runningMean.value += (mean - runningMean.value) * (1 - momentum)
        runningVariance.value += (variance - runningVariance.value) * (1 - momentum)
        let normalizer = rsqrt(variance + epsilon) * scale
        return (input - mean) * normalizer + offset
    }
    
    @differentiable
    public func forwardInference(to input: Tensor<Scalar>) -> Tensor<Scalar> {
        let mean = runningMean.value
        let variance = runningVariance.value
        let normalizer = rsqrt(variance + epsilon) * scale
        return (input - mean) * normalizer + offset
    }
}

public struct ConvBN<Scalar: TensorFlowFloatingPoint>: FALayer {
    public var conv: FANoBiasConv2D<Scalar>
    public var norm: FABatchNorm<Scalar>
    @noDerivative public var delegate: LayerDelegate<Output> = LayerDelegate()
    
    public init(_ cIn: Int, _ cOut: Int, ks: Int = 3, stride: Int = 2){
        // TODO (when control flow AD works): use Conv2D without bias
        self.conv = FANoBiasConv2D(filterShape: (ks, ks, cIn, cOut), 
                           strides: (stride,stride), 
                           padding: .same, 
                           activation: relu)
        self.norm = FABatchNorm(featureCount: cOut, epsilon: 1e-5)
    }

    @differentiable
    public func forward(_ input: Tensor<Scalar>) -> Tensor<Scalar> {
        return norm(conv(input))
    }
}

public struct CnnModelBN: Layer {
    public var convs: [ConvBN<Float>]
    public var pool = FAAdaptiveAvgPool2D<Float>()
    public var flatten = Flatten<Float>()
    public var linear: FADense<Float>
    
    public init(channelIn: Int, nOut: Int, filters: [Int]){
        convs = []
        let allFilters = [channelIn] + filters
        for i in 0..<filters.count { convs.append(ConvBN(allFilters[i], allFilters[i+1])) }
        linear = FADense<Float>(inputSize: filters.last!, outputSize: nOut)
    }
    
    @differentiable
    public func call(_ input: TF) -> TF {
        return input.sequenced(through: convs, pool, flatten, linear)
    }
}
