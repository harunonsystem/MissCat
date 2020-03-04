//
//  Note.swift
//  MissCat
//
//  Created by Yuiga Wada on 2019/11/12.
//  Copyright © 2019 Yuiga Wada. All rights reserved.
//

import Agrume
import MisskeyKit
import RxCocoa
import RxDataSources
import RxSwift
import SkeletonView
import UIKit
import WebKit

public protocol NoteCellDelegate {
    func tappedReply()
    func tappedRenote()
    func tappedReaction(noteId: String, iconUrl: String?, displayName: String, username: String, note: NSAttributedString, hasFile: Bool, hasMarked: Bool)
    func tappedOthers()
    
    func tappedLink(text: String)
    func move2Profile(userId: String)
}

private typealias ViewModel = NoteCellViewModel
typealias ReactionsDataSource = RxCollectionViewSectionedReloadDataSource<NoteCell.Reaction.Section>

public class NoteCell: UITableViewCell, UITextViewDelegate, ReactionCellDelegate, UICollectionViewDelegate {
    // MARK: IBOutlet (UIView)
    
    @IBOutlet weak var nameTextView: MisskeyTextView!
    
    @IBOutlet weak var iconView: UIImageView!
    
    @IBOutlet weak var agoLabel: UILabel!
    
    @IBOutlet weak var noteView: MisskeyTextView!
    
    @IBOutlet weak var fileImageView: UIStackView!
    @IBOutlet weak var fileImageContainer: UIView!
    
    @IBOutlet weak var reactionsCollectionView: UICollectionView!
    
    @IBOutlet weak var pollView: PollView!
    
    @IBOutlet weak var replyButton: UIButton!
    @IBOutlet weak var renoteButton: UIButton!
    @IBOutlet weak var reactionButton: UIButton!
    @IBOutlet weak var othersButton: UIButton!
    
    @IBOutlet weak var separatorBorder: UIView!
    @IBOutlet weak var replyIndicator: UIView!
    
    @IBOutlet weak var mainStackView: UIStackView!
    
    // MARK: IBOutlet (Constraint)
    
    @IBOutlet weak var displayName2MainStackConstraint: NSLayoutConstraint!
    @IBOutlet weak var icon2MainStackConstraint: NSLayoutConstraint!
    @IBOutlet weak var reactionCollectionHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pollViewHeightConstraint: NSLayoutConstraint!
    
    // MARK: Public Var
    
    public var delegate: NoteCellDelegate?
    public var noteId: String?
    public var userId: String?
    public var iconImageUrl: String?
    
    // MARK: Private Var
    
    private let disposeBag = DisposeBag()
    private lazy var reactionsDataSource = self.setupDataSource()
    private var viewModel: ViewModel?
    
    private func getViewModel(item: NoteCell.Model, isDetailMode: Bool) -> ViewModel {
        let input: ViewModel.Input = .init(cellModel: item,
                                           isDetailMode: isDetailMode,
                                           noteYanagi: noteView,
                                           nameYanagi: nameTextView)
        
        let viewModel = NoteCellViewModel(with: input, and: disposeBag)
        
        binding(viewModel: viewModel)
        return viewModel
    }
    
    // MARK: Life Cycle
    
    public override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        contentView.bounds.size = targetSize
        contentView.layoutIfNeeded()
        return super.systemLayoutSizeFitting(targetSize,
                                             withHorizontalFittingPriority: horizontalFittingPriority,
                                             verticalFittingPriority: verticalFittingPriority)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        setupView()
        setupComponents()
    }
    
    private lazy var setupView: (() -> Void) = { // 必ず一回しか読み込まれない
        self.setupSkeltonMode()
        self.setupProfileGesture() // プロフィールに飛ぶtapgestureを設定する
        self.setupCollectionView()
        return {}
    }()
    
    private func setupCollectionView() {
        reactionsCollectionView.backgroundColor = .clear
        
        let flowLayout = UICollectionViewFlowLayout()
        let width = mainStackView.frame.width / 6
        
        flowLayout.itemSize = CGSize(width: width, height: 30)
        //        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumInteritemSpacing = 5
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        reactionsCollectionView.collectionViewLayout = flowLayout
    }
    
    private func setupDataSource() -> ReactionsDataSource {
        reactionsCollectionView.register(UINib(nibName: "ReactionCell", bundle: nil), forCellWithReuseIdentifier: "ReactionCell")
        reactionsCollectionView.rx.setDelegate(self).disposed(by: disposeBag)
        
        let dataSource = ReactionsDataSource(
            configureCell: { dataSource, collectionView, indexPath, _ in
                self.setupReactionCell(dataSource, collectionView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func setupComponents() {
        // ["FontAwesome5Free-Solid", "FontAwesome5Free-Regular"], ["FontAwesome5Brands-Regular"]
        
        iconView.layoutIfNeeded()
        
        iconView.layer.cornerRadius = iconView.frame.height / 2
        replyButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        renoteButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        reactionButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        othersButton.titleLabel?.font = .awesomeSolid(fontSize: 15.0)
        
        noteView.delegate = self
        
        noteView.isUserInteractionEnabled = true
        
        if fileImageView.arrangedSubviews.count > 0 {
            fileImageContainer.translatesAutoresizingMaskIntoConstraints = false
        }
    }
    
    private func binding(viewModel: ViewModel) {
        let output = viewModel.output
        
        output.reactions.asDriver(onErrorDriveWith: Driver.empty()).drive(reactionsCollectionView.rx.items(dataSource: reactionsDataSource)).disposed(by: disposeBag)
        output.reactions.asDriver(onErrorDriveWith: Driver.empty()).map { // リアクションの数が0のときはreactionsCollectionViewを非表示に
            guard $0.count == 1 else { return true }
            return $0[0].items.count == 0
        }.drive(reactionsCollectionView.rx.isHidden).disposed(by: disposeBag)
        
        output.reactions.asDriver(onErrorDriveWith: Driver.empty()).map { // リアクションの数によってreactionsCollectionViewの高さを調節
            guard $0.count == 1 else { return 30 }
            let count = $0[0].items.count
            let step = ceil(Double(count) / 5)
            
            return CGFloat(step * 40)
        }.drive(reactionCollectionHeightConstraint.rx.constant).disposed(by: disposeBag)
        
        output.poll.asDriver(onErrorDriveWith: Driver.empty()).drive(onNext: { poll in
            self.pollView.isHidden = false
            self.pollView.setPoll(with: poll)
            self.pollViewHeightConstraint.constant = self.pollView.height
        }).disposed(by: disposeBag)
        
        output.ago.asDriver(onErrorDriveWith: Driver.empty()).drive(agoLabel.rx.text).disposed(by: disposeBag)
        output.name.asDriver(onErrorDriveWith: Driver.empty()).drive(nameTextView.rx.attributedText).disposed(by: disposeBag)
        
        output.shapedNote.asDriver(onErrorDriveWith: Driver.empty()).drive(noteView.rx.attributedText).disposed(by: disposeBag)
        output.shapedNote.asDriver(onErrorDriveWith: Driver.empty()).map { $0 == nil }.drive(noteView.rx.isHidden).disposed(by: disposeBag) // 画像onlyや投票onlyの場合、noteが存在しない場合がある→ noteViewを非表示にする
        
        output.iconImage.asDriver(onErrorDriveWith: Driver.empty()).drive(iconView.rx.image).disposed(by: disposeBag)
        
        output.defaultConstraintActive.asDriver(onErrorDriveWith: Driver.empty()).drive(displayName2MainStackConstraint.rx.active).disposed(by: disposeBag)
        output.defaultConstraintActive.asDriver(onErrorDriveWith: Driver.empty()).drive(icon2MainStackConstraint.rx.active).disposed(by: disposeBag)
        
        output.backgroundColor.asDriver(onErrorDriveWith: Driver.empty()).drive(rx.backgroundColor).disposed(by: disposeBag)
        
        output.isReplyTarget.asDriver(onErrorDriveWith: Driver.empty()).drive(separatorBorder.rx.isHidden).disposed(by: disposeBag)
        output.isReplyTarget.map { !$0 }.asDriver(onErrorDriveWith: Driver.empty()).drive(replyIndicator.rx.isHidden).disposed(by: disposeBag)
    }
    
    private func setupProfileGesture() {
        let gestureTargets = [iconView, nameTextView]
        
        gestureTargets.forEach {
            guard let view = $0 else { return }
            view.setTapGesture(disposeBag) {
                guard let delegate = self.delegate, let userId = self.userId else { return }
                delegate.move2Profile(userId: userId)
            }
        }
    }
    
    private func changeStateFileImage(isHidden: Bool) {
        fileImageView.isHidden = isHidden
        fileImageContainer.isHidden = isHidden
    }
    
    // MARK: Public Methods
    
    public func initializeComponent(hasFile: Bool) {
        delegate = nil
        noteId = nil
        userId = nil
        
        backgroundColor = .white
        separatorBorder.isHidden = false
        replyIndicator.isHidden = true
        
        nameTextView.attributedText = nil
        iconView.image = nil
        agoLabel.text = nil
        noteView.attributedText = nil
        noteView.isHidden = false
        
        //        reactionsCollectionView.isHidden = false
        
        setupFileView()
        fileImageView.arrangedSubviews.forEach {
            guard let imageView = $0 as? UIImageView else { return }
            imageView.isHidden = true
            imageView.image = nil
        }
        
        // TODO: reactionを隠す時これつかう → UIView.animate(withDuration: 0.25, animations: { () -> Void in
        
        changeStateFileImage(isHidden: !hasFile)
        
        replyButton.setTitle("", for: .normal)
        renoteButton.setTitle("", for: .normal)
        reactionButton.setTitle("", for: .normal)
        
        //        self.nameTextView.resetViewString()
        //        self.noteView.resetViewString()
        pollView.isHidden = true
        pollView.initialize()
    }
    
    // ファイルは同時に4つしか載せることができないので、先に4つViewを追加しておく
    private func setupFileView() {
        guard fileImageView.arrangedSubviews.count == 0 else { return }
        
        for _ in 0 ..< 4 {
            let imageView = UIImageView()
            
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isHidden = true
            imageView.layer.cornerRadius = 10
            imageView.isUserInteractionEnabled = true
            imageView.backgroundColor = .lightGray
            imageView.layer.borderColor = UIColor.lightGray.cgColor
            imageView.layer.borderWidth = 1
            imageView.layer.masksToBounds = true
            
            fileImageView.addArrangedSubview(imageView)
        }
    }
    
    public func setupFileImage(_ image: UIImage, originalImageUrl: String, index: Int) {
        // self.changeStateFileImage(isHidden: false) //メインスレッドでこれ実行するとStackViewの内部計算と順番が前後するのでダメ
        
        DispatchQueue.main.async {
            guard let imageView = self.getFileView(index) else { return }
            
            //tap gestureを付加する
            imageView.setTapGesture(self.disposeBag, closure: { self.showImage(url: originalImageUrl) })
            
            imageView.backgroundColor = .clear
            imageView.image = image
            imageView.isHidden = false
            
            imageView.layoutIfNeeded()
            self.mainStackView.setNeedsLayout()
        }
    }
    
    private func getFileView(_ index: Int) -> UIImageView? {
        guard index < fileImageView.arrangedSubviews.count,
            let imageView = self.fileImageView.arrangedSubviews[index] as? UIImageView else { return nil }
        
        return imageView
    }
    
    private func showImage(url: String) {
        guard let url = URL(string: url), let delegate = self.delegate as? UIViewController else { return }
        
        let agrume = Agrume(url: url)
        agrume.show(from: delegate) // 画像を表示
    }
    
    private func setupReactionCell(_ dataSource: CollectionViewSectionedDataSource<NoteCell.Reaction.Section>, _ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell {
        guard let viewModel = viewModel else { fatalError("Internal Error.") }
        
        let index = indexPath.row
        let reactionsModel = viewModel.reactionsModel
        
        guard let cell = reactionsCollectionView.dequeueReusableCell(withReuseIdentifier: "ReactionCell", for: indexPath) as? ReactionCell else { fatalError("Internal Error.") }
        
        if index < reactionsModel.count {
            let item = reactionsModel[index]
            
            let shapedCell = viewModel.setReactionCell(with: item, to: cell)
            shapedCell.delegate = self
            
            return shapedCell
        }
        
        return cell
    }
    
    public func shapeCell(item: NoteCell.Model, isDetailMode: Bool = false) -> NoteCell {
        guard !item.isSkelton else { // SkeltonViewを表示する
            changeSkeltonState(on: true)
            return self
        }
        
        // Font
        noteView.font = UIFont(name: "Helvetica",
                               size: isDetailMode ? 15.0 : 11.0)
        nameTextView.font = UIFont(name: "Helvetica",
                                   size: 10.0)
        
        nameTextView.xMargin = 0
        nameTextView.yMargin = 0
        
        noteView.xMargin = 0
        noteView.yMargin = 0
        
        reactionsCollectionView.isHidden = true // リアクションが存在しない場合はHideする
        
        // 余白消す
        nameTextView.textContainerInset = .zero
        nameTextView.textContainer.lineFragmentPadding = 0
        
        changeSkeltonState(on: false)
        
        guard let noteId = item.noteId else { return NoteCell() }
        
        initializeComponent(hasFile: item.files.count > 0) // Initialize because NoteCell is reused by TableView.
        
        // main
        self.noteId = item.noteId
        userId = item.userId
        
        // YanagiTextと一対一にキャッシュを保存できるように、idをYanagiTextに渡す
        noteView.setId(noteId: item.noteId)
        nameTextView.setId(userId: item.userId)
        
        let viewModel = getViewModel(item: item, isDetailMode: isDetailMode)
        self.viewModel = viewModel
        viewModel.setCell()
        
        iconImageUrl = viewModel.setImage(username: item.username, imageRawUrl: item.iconImageUrl)
        
        // file
        if let files = Cache.shared.getFiles(noteId: noteId) { // キャッシュが存在する場合
            for index in 0 ..< files.count {
                let file = files[index]
                setupFileImage(file.thumbnail, originalImageUrl: file.originalUrl, index: index)
            }
        } else { // キャッシュが存在しない場合
            let files = item.files
            let fileCount = files.count
            
            for index in 0 ..< fileCount {
                let file = files[index]
                
                guard let thumbnailUrl = file.thumbnailUrl,
                    let original = file.url,
                    let imageView = self.getFileView(index) else { break }
                
                imageView.isHidden = false
                
                thumbnailUrl.toUIImage { image in
                    guard let image = image else { return }
                    
                    Cache.shared.saveFiles(noteId: noteId, image: image, originalUrl: original)
                    self.setupFileImage(image, originalImageUrl: original, index: index)
                }
            }
        }
        
        // footer
        let replyCount = item.replyCount != 0 ? String(item.replyCount) : ""
        let renoteCount = item.renoteCount != 0 ? String(item.renoteCount) : ""
        var reactionsCount: Int = 0
        item.reactions.forEach {
            reactionsCount += Int($0.count ?? "0") ?? 0
        }
        
        replyButton.setTitle("reply\(replyCount)", for: .normal)
        renoteButton.setTitle("retweet\(renoteCount)", for: .normal)
        reactionButton.setTitle("plus\(reactionsCount == 0 ? "" : String(reactionsCount))", for: .normal)
        
        // reaction
        
        return self
    }
    
    // MARK: Utilities
    
    private func setupSkeltonMode() {
        separatorBorder.isSkeletonable = true
        replyIndicator.isSkeletonable = true
        
        nameTextView.isSkeletonable = true
        iconView.isSkeletonable = true
        agoLabel.isSkeletonable = true
        noteView.isSkeletonable = true
        
        reactionsCollectionView.isSkeletonable = true
        
        fileImageView.isSkeletonable = true
    }
    
    private func changeSkeltonState(on: Bool) {
        if on {
            nameTextView.text = nil
            agoLabel.text = nil
            noteView.text = nil
            
            nameTextView.showAnimatedGradientSkeleton()
            iconView.showAnimatedGradientSkeleton()
            
            reactionsCollectionView.isHidden = true
            pollView.isHidden = true
            
            fileImageView.showAnimatedGradientSkeleton()
        } else {
            nameTextView.hideSkeleton()
            iconView.hideSkeleton()
            
            fileImageView.hideSkeleton()
        }
    }
    
    // MARK: DELEGATE
    
    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if let delegate = delegate {
            delegate.tappedLink(text: URL.absoluteString)
        }
        
        return false
    }
    
    public func tappedReaction(noteId: String, reaction: String, isRegister: Bool) {
        guard let viewModel = viewModel else { return }
        
        if isRegister {
            viewModel.registerReaction(noteId: noteId, reaction: reaction)
        } else {
            viewModel.cancelReaction(noteId: noteId)
        }
    }
    
    // MARK: IBAction
    
    @IBAction func tappedReply(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedReply()
    }
    
    @IBAction func tappedRenote(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedRenote()
    }
    
    @IBAction func tappedReaction(_ sender: Any) {
        guard let delegate = delegate, let noteId = self.noteId, let viewModel = viewModel else { return }
        
        delegate.tappedReaction(noteId: noteId,
                                iconUrl: iconImageUrl,
                                displayName: viewModel.output.displayName,
                                username: viewModel.output.username,
                                note: noteView.attributedText,
                                hasFile: false,
                                hasMarked: false)
    }
    
    @IBAction func tappedOthers(_ sender: Any) {
        guard let delegate = delegate else { return }
        delegate.tappedOthers()
    }
}

// MARK: NoteCell.Model

extension NoteCell {
    public struct Model: IdentifiableType, Equatable {
        var isSkelton = false
        var isReactionGenCell = false
        var isRenoteeCell = false
        var renotee: String?
        var baseNoteId: String? // どのcellに対するReactionGenCellなのか
        var isReply: Bool = false // リプライであるかどうか
        var isReplyTarget: Bool = false // リプライ先の投稿であるかどうか
        
        public let identity: String = String(Float.random(in: 1 ..< 100))
        let noteId: String?
        
        public typealias Identity = String
        
        let iconImageUrl: String?
        var iconImage: UIImage?
        
        let userId: String
        let displayName: String
        let username: String
        let note: String
        let ago: String
        let replyCount: Int
        let renoteCount: Int
        var reactions: [ReactionCount]
        var shapedReactions: [NoteCell.Reaction]
        var myReaction: String?
        let files: [File]
        let emojis: [EmojiModel]?
        
        let poll: Poll?
        
        public static func == (lhs: NoteCell.Model, rhs: NoteCell.Model) -> Bool {
            return lhs.identity == rhs.identity
        }
        
        static func fakeRenoteecell(renotee: String, baseNoteId: String) -> NoteCell.Model {
            var renotee = renotee
            if renotee.count > 7 {
                renotee = String(renotee.prefix(10)) + "..."
            }
            
            return NoteCell.Model(isRenoteeCell: true,
                                  renotee: renotee,
                                  baseNoteId: baseNoteId,
                                  noteId: "",
                                  iconImageUrl: "",
                                  iconImage: nil,
                                  userId: "",
                                  displayName: "",
                                  username: "",
                                  note: "",
                                  ago: "",
                                  replyCount: 0,
                                  renoteCount: 0,
                                  reactions: [],
                                  shapedReactions: [],
                                  myReaction: nil,
                                  files: [],
                                  emojis: [],
                                  poll: nil)
        }
        
        static func fakeSkeltonCell() -> NoteCell.Model {
            return NoteCell.Model(isSkelton: true,
                                  isRenoteeCell: false,
                                  renotee: "",
                                  baseNoteId: "",
                                  noteId: "",
                                  iconImageUrl: "",
                                  iconImage: nil,
                                  userId: "",
                                  displayName: "",
                                  username: "",
                                  note: "",
                                  ago: "",
                                  replyCount: 0,
                                  renoteCount: 0,
                                  reactions: [],
                                  shapedReactions: [],
                                  myReaction: nil,
                                  files: [],
                                  emojis: [],
                                  poll: nil)
        }
    }
    
    struct Section {
        var items: [Model]
    }
    
    struct Reaction: IdentifiableType, Equatable {
        typealias Identity = String
        var identity: String
        var noteId: String
        
        var url: String?
        var rawEmoji: String?
        
        var isMyReaction: Bool
        
        var count: String
        
        struct Section {
            var items: [Reaction]
        }
    }
}

extension NoteCell.Section: AnimatableSectionModelType {
    typealias Item = NoteCell.Model
    typealias Identity = String
    
    public var identity: String {
        return ""
    }
    
    init(original: NoteCell.Section, items: [NoteCell.Model]) {
        self = original
        self.items = items
    }
}

extension NoteCell.Reaction.Section: AnimatableSectionModelType {
    typealias Item = NoteCell.Reaction
    typealias Identity = String
    
    public var identity: String {
        return ""
    }
    
    init(original: Item.Section, items: [Item]) {
        self = original
        self.items = items
    }
}

extension NoteCell.Model {
    /// ReactionCountをNoteCell.Reactionに変換する
    func getReactions() -> [NoteCell.Reaction] {
        return reactions.map { reaction in
            guard let count = reaction.count, count != "0" else { return nil }
            
            let rawEmoji = reaction.name ?? ""
            let isMyReaction = rawEmoji == self.myReaction
            
            guard rawEmoji != "", let convertedEmojiData = EmojiHandler.handler.convertEmoji(raw: rawEmoji) else {
                // If being not converted
                let reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                      noteId: self.noteId ?? "",
                                                      url: nil,
                                                      rawEmoji: rawEmoji,
                                                      isMyReaction: isMyReaction,
                                                      count: count)
                return reactionModel
            }
            
            var reactionModel: NoteCell.Reaction
            switch convertedEmojiData.type {
            case "default":
                reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                  noteId: self.noteId ?? "",
                                                  url: nil,
                                                  rawEmoji: convertedEmojiData.emoji,
                                                  isMyReaction: isMyReaction,
                                                  count: count)
            case "custom":
                reactionModel = NoteCell.Reaction(identity: UUID().uuidString,
                                                  noteId: self.noteId ?? "",
                                                  url: convertedEmojiData.emoji,
                                                  rawEmoji: convertedEmojiData.emoji,
                                                  isMyReaction: isMyReaction,
                                                  count: count)
            default:
                return nil
            }
            
            return reactionModel
        }.compactMap { $0 } // nil除去
    }
}