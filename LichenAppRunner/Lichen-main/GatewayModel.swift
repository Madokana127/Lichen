import Foundation

extension GatewayMethod {
    /// 查询网关可用模型列表的候选方法名。
    ///
    /// 不同网关实现可能使用不同命名；这里集中定义，便于按真实协议调整。
    public static let modelList = "model.list"
    public static let modelsList = "models.list"
    public static let availableModels = "model.available"
}
