package lrr4cj.controllers

import cjoy.*
import lrr4cj.models.*
import lrr4cj.dao.*
import lrr4cj.middleware.*
import stdx.net.http.HttpStatusCode

/**
 * 单行本控制器
 */
public class TankoubonController {
    /**
     * 获取所有单行本
     */
    public static func getTankoubons(ctx: JoyContext) {
        let tankoubons = TankoubonModel.getAllTankoubons()
        var result = "{\"filtered\":${tankoubons.size},\"result\":["
        for (i in 0..tankoubons.size) {
            if (i > 0) { result += "," }
            result += tankoubons[i].toJson()
        }
        result += "],\"total\":${tankoubons.size}}"
        
        ctx.json(result)
    }
    
    /**
     * 根据ID获取单行本
     */
    public static func getTankoubonById(ctx: JoyContext) {
        let id = ctx.getParam("id") ?? ""
        let userIdOpt = AuthMiddleware.optionalUser(ctx)
        let tankoubon = match (userIdOpt) {
            case Some(userId) => TankoubonModel.getTankoubonByIdWithUser(id, userId)
            case None => TankoubonModel.getTankoubonById(id)
        }
        
        if (tankoubon.id.size == 0) {
            let errorResponse = "{\"error\":\"The given tankoubon does not exist.\",\"operation\":\"get_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
            return
        }

        // 查询收藏状态（登录用户）
        match (userIdOpt) {
            case Some(userId) => tankoubon.isfavorite = UserTankoubonFavoriteDao.isFavorite(userId, id)
            case None => tankoubon.isfavorite = false
        }
        
        var result = "{\"filtered\":${tankoubon.archives.size},\"result\":${tankoubon.toJson()},\"total\":${tankoubon.archives.size}}"
        ctx.json(result)
    }
    
    /**
     * 创建新单行本
     */
    public static func createTankoubon(ctx: JoyContext) {
        let name = ctx.getQuery("name") ?? ""
        
        if (name.size == 0) {
            let errorResponse = "{\"error\":\"Tankoubon name not specified.\",\"operation\":\"create_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
            return
        }
        
        let tankoubon = TankoubonModel.createTankoubon(name)
        let successResponse = "{\"operation\":\"create_tankoubon\",\"success\":1,\"tankoubon_id\":\"${tankoubon.id}\"}"
        ctx.json(successResponse)
    }
    
    /**
     * 更新单行本
     */
    public static func updateTankoubon(ctx: JoyContext) {
        let id = ctx.getParam("id") ?? ""
        let name = ctx.getQuery("name") ?? ""
        let summary = ctx.getQuery("summary") ?? ""
        
        let success = TankoubonModel.updateTankoubon(id, name, summary, "", [])
        if (success) {
            let successResponse = "{\"error\":\"\",\"operation\":\"update_tankoubon\",\"success\":1,\"successMessage\":\"Updated tankoubon \\\"${name}\\\"!\"}"
            ctx.json(successResponse)
        } else {
            let errorResponse = "{\"error\":\"Tankoubon doesn't exist in the database!\",\"operation\":\"update_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
        }
    }
    
    /**
     * 删除单行本
     */
    public static func deleteTankoubon(ctx: JoyContext) {
        let id = ctx.getParam("id") ?? ""
        
        let success = TankoubonModel.deleteTankoubon(id)
        if (success) {
            let successResponse = "{\"error\":\"\",\"operation\":\"delete_tankoubon\",\"success\":1,\"successMessage\":null}"
            ctx.json(successResponse)
        } else {
            let errorResponse = "{\"error\":\"Locked resource: ${id}\",\"operation\":\"delete_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
        }
    }
    
    /**
     * 向单行本添加档案
     */
    public static func addArchiveToTankoubon(ctx: JoyContext) {
        let tankoubonId = ctx.getParam("id") ?? ""
        let archiveId = ctx.getParam("archive") ?? ""
        
        let success = TankoubonModel.addArchiveToTankoubon(tankoubonId, archiveId)
        if (success) {
            let successResponse = "{\"error\":\"\",\"operation\":\"add_to_tankoubon\",\"success\":1,\"successMessage\":\"Added archive to tankoubon!\"}"
            ctx.json(successResponse)
        } else {
            let errorResponse = "{\"error\":\"Tankoubon doesn't exist in the database!\",\"operation\":\"add_to_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
        }
    }
    
    /**
     * 从单行本移除档案
     */
    public static func removeArchiveFromTankoubon(ctx: JoyContext) {
        let tankoubonId = ctx.getParam("id") ?? ""
        let archiveId = ctx.getParam("archive") ?? ""
        
        let success = TankoubonModel.removeArchiveFromTankoubon(tankoubonId, archiveId)
        if (success) {
            let successResponse = "{\"error\":\"\",\"operation\":\"remove_from_tankoubon\",\"success\":1,\"successMessage\":\"Removed archive from tankoubon!\"}"
            ctx.json(successResponse)
        } else {
            let errorResponse = "{\"error\":\"Tankoubon doesn't exist in the database!\",\"operation\":\"remove_from_tankoubon\",\"success\":0}"
            ctx.json(errorResponse)
        }
    }

    /**
     * 添加收藏（PUT /api/tankoubons/{id}/favorite）
     */
    public static func addFavorite(ctx: JoyContext): Unit {
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id") ?? ""
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_tankoubon_favorite\",\"error\":\"No tankoubon ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                let tank = TankoubonModel.getTankoubonById(id)
                if (tank.id.size == 0) {
                    let errorResponse = "{\"operation\":\"add_tankoubon_favorite\",\"error\":\"Tankoubon not found\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_NOT_FOUND)
                    ctx.json(errorResponse)
                    return
                }

                let addSuccess = UserTankoubonFavoriteDao.addFavorite(userId, id)
                if (addSuccess) {
                    let result = "{\"operation\":\"add_tankoubon_favorite\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"add_tankoubon_favorite\",\"error\":\"Failed to add favorite\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return
        }
    }

    /**
     * 取消收藏（DELETE /api/tankoubons/{id}/favorite）
     */
    public static func removeFavorite(ctx: JoyContext): Unit {
        match (AuthMiddleware.requireUser(ctx)) {
            case Some(userId) =>
                let id = ctx.getParam("id") ?? ""
                if (id.size == 0) {
                    let errorResponse = "{\"operation\":\"remove_tankoubon_favorite\",\"error\":\"No tankoubon ID specified.\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_BAD_REQUEST)
                    ctx.json(errorResponse)
                    return
                }

                let removeSuccess = UserTankoubonFavoriteDao.removeFavorite(userId, id)
                if (removeSuccess) {
                    let result = "{\"operation\":\"remove_tankoubon_favorite\",\"success\":1}"
                    ctx.json(result)
                } else {
                    let errorResponse = "{\"operation\":\"remove_tankoubon_favorite\",\"error\":\"Failed to remove favorite\",\"success\":0}"
                    ctx.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR)
                    ctx.json(errorResponse)
                }
            case None => return
        }
    }
}
