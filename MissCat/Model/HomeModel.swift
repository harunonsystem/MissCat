//
//  HomeModel.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/26.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import MisskeyKit

class HomeModel {
    func vote(choice: Int, to noteId: String) {
        MisskeyKit.notes.vote(noteId: noteId, choice: choice, result: { _, _ in
            //            print(error)
        })
    }
    
    func renote(noteId: String) {
        MisskeyKit.notes.renote(renoteId: noteId) { _, _ in
            //            print(error)
        }
    }
}
