import MetadataViews from "./MetadataViews.cdc"
import NonFungibleToken from "../NonFungibleToken.cdc"

pub contract FLOAT: NonFungibleToken {

    pub enum ClaimOptions: UInt8 {
        pub case Unlimited
        pub case Limited
        pub case Admin
    }

    // Paths
    //
    pub let FLOATCollectionStoragePath: StoragePath
    pub let FLOATCollectionPublicPath: PublicPath
    pub let FLOATEventsStoragePath: StoragePath
    pub let FLOATEventsPublicPath: PublicPath
    pub let FLOATEventsPrivatePath: PrivatePath

    pub var totalSupply: UInt64

    pub event ContractInitialized()
    // Throw away for standard
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)

    pub event FLOATMinted(recipient: Address, info: FLOATEventInfo)
    pub event FLOATDeposited(to: Address, host: Address, name: String, id: UInt64)
    pub event FLOATWithdrawn(from: Address, host: Address, name: String, id: UInt64)

    pub resource NFT: NonFungibleToken.INFT, MetadataViews.Resolver {
        pub let id: UInt64
        pub let info: MetadataViews.FLOATMetadataView

        pub fun getViews(): [Type] {
             return [
                Type<MetadataViews.FLOATMetadataView>(),
                Type<MetadataViews.Identifier>(),
                Type<MetadataViews.Display>()
            ]
        }

        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.FLOATMetadataView>():
                    return self.info
                case Type<MetadataViews.Identifier>():
                    return MetadataViews.Identifier(id: self.id, address: self.owner!.address) 
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                                                 name: self.info.name, 
                                                 description: self.info.description, 
                                                 file: MetadataViews.IPFSFile(cid: self.info.image, path: nil)
                                                )
            }

            return nil
        }

        init(_recipient: Address, _info: FLOATEventInfo, _serial: UInt64) {
            self.id = self.uuid
            self.info = MetadataViews.FLOATMetadataView(
                                                        _recipient: _recipient, 
                                                        _host: _info.host, 
                                                        _name: _info.name, 
                                                        _description: _info.description, 
                                                        _image: _info.image,
                                                        _serial: _serial
                                                       )

            let dateReceived = 0.0 // getCurrentBlock().timestamp
            emit FLOATMinted(recipient: _recipient, info: _info)

            FLOAT.totalSupply = FLOAT.totalSupply + 1
        }
    }

    pub resource Collection: NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection {
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        pub fun deposit(token: @NonFungibleToken.NFT) {
            let nft <- token as! @NFT
            emit FLOATDeposited(to: nft.info.recipient, host: nft.info.host, name: nft.info.name, id: nft.uuid)
            self.ownedNFTs[nft.uuid] <-! nft
        }

        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            pre {
                false: "The withdraw function is disabled."
            }
            return <- create NFT(_recipient: 0x0, _info: FLOATEventInfo(_host: 0x0, _name: "", _description: "", _image: ""), _serial: 0)
        }

        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT
        }

        pub fun borrowViewResolver(id: UInt64): &{MetadataViews.Resolver} {
            let tokenRef = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT
            let nftRef = tokenRef as! &NFT
            return nftRef as &{MetadataViews.Resolver}
        }

        init() {
            self.ownedNFTs <- {}
        }

        destroy() {
            destroy self.ownedNFTs
        }
    }

    pub struct interface FLOATEvent {
        pub let type: ClaimOptions
        pub let info: FLOATEventInfo
    }

    pub struct FLOATEventInfo {
        pub let host: Address
        pub let name: String
        pub let description: String 
        pub let image: String 
        pub let dateCreated: UFix64

        // Effectively the current serial number
        pub(set) var totalSupply: UInt64
        // Maps a user's address to its serial number
        pub(set) var claimed: {Address: UInt64}
        // A manual switch for the host to be able to turn off
        pub(set) var active: Bool
        init(_host: Address, _name: String, _description: String, _image: String) {
            self.host = _host
            self.name = _name
            self.description = _description
            self.image = _image
            self.dateCreated = 0.0 // getCurrentBlock().timestamp
            self.totalSupply = 0
            self.claimed = {}
            self.active = true
        }
    }

    pub struct Unlimited: FLOATEvent {
        pub let type: ClaimOptions
        pub let info: FLOATEventInfo

        init(_host: Address, _name: String, _description: String, _image: String) {
            self.type = ClaimOptions.Unlimited
            self.info = FLOATEventInfo(_host: _host, _name: _name, _description: _description, _image: _image)
        }
    }

    pub struct Limited: FLOATEvent {
        pub let type: ClaimOptions
        pub let info: FLOATEventInfo
        
        /* Section for Time Limited declarations */
        // An automatic switch handled by the contract
        // to stop people from claiming after a certain time.
        pub let timeLimited: Bool
        pub let timePeriod: UFix64?
        pub let dateEnding: UFix64?

        /* Section for Secret Code Limited declarations */
        pub let secretCodeLimited: Bool
        // A list of accounts to see who has put in a code.
        // Maps their address to the code they put in.
        pub(set) var secretCodeAccounts: {Address: String}
        // The secret code, set by the owner of this event.
        pub(set) var secretPhrase: String?

        /* Section for Capacity Limited declarations */
        pub let capacityLimited: Bool
        // A list of accounts to get track on who is here first
        // Maps the position of who come first to their address.
        pub(set) var capacityAccounts: {UInt64: Address}
        pub let capacity: UInt64?

        init(_host: Address, _name: String, _description: String, _image: String, _timeLimited: Bool, _timePeriod: UFix64?, _secretCodeLimited: Bool, _capacityLimited: Bool, _capacity: UInt64?) {
            self.type = ClaimOptions.Limited
            self.info = FLOATEventInfo(_host: _host, _name: _name, _description: _description, _image: _image)
            
            /* Time Limited */
            if _timeLimited {
                assert(_timePeriod != nil, message: "Time Period should not be nil if Time Limited FLOAT is to be created")
                self.timePeriod = _timePeriod
                self.dateEnding = self.info.dateCreated + _timePeriod!
            } else {
                self.timePeriod = nil
                self.dateEnding = nil
            }
            self.timeLimited = _timeLimited

            /* Secret Code Limited */
            if _secretCodeLimited {
                self.secretCodeAccounts = {}
                self.secretPhrase = ""
            } else {
                self.secretCodeAccounts = {}
                self.secretPhrase = nil
            }
            self.secretCodeLimited = _secretCodeLimited

            /* Capacity Limited */
            if _capacityLimited {
                assert(_capacity != nil, message: "Capacity should not be nil if Capacity Limited FLOAT is to be created")
                self.capacityAccounts = {}
                self.capacity = _capacity
            } else {
                self.capacityAccounts = {}
                self.capacity = nil
            }
            self.capacityLimited = _capacityLimited
        }
    }

    // For an Admin to distribute directly to whomever.
    pub struct Admin: FLOATEvent {
        pub let type: ClaimOptions
        pub let info: FLOATEventInfo

        init(_host: Address, _name: String, _description: String, _image: String) {
            self.type = ClaimOptions.Admin
            self.info = FLOATEventInfo(_host: _host, _name: _name, _description: _description, _image: _image)
        }
    }

    pub resource interface FLOATEventsPublic {
        pub fun getEvent(name: String): {FLOATEvent}
        pub fun getAllEvents(): {String: {FLOATEvent}}
        pub fun addCreationCapability(minter: Capability<&FLOATEvents>) 
        pub fun claim(name: String, recipient: &Collection, secret: String?)
    }

    pub resource FLOATEvents: FLOATEventsPublic {
        access(self) var events: {String: {FLOATEvent}}
        access(self) var otherHosts: {Address: Capability<&FLOATEvents>}

        // Create a new FLOAT Event.
        pub fun createEvent(type: ClaimOptions, name: String, description: String, image: String, timeLimited: Bool?, timePeriod: UFix64?, secretCodeLimited: Bool?, capacityLimited: Bool?, capacity: UInt64?) {
            pre {
                self.events[name] == nil: 
                    "An event with this name already exists in your Collection."
                type != ClaimOptions.Limited && timeLimited != true && timePeriod == nil && secretCodeLimited != true && capacityLimited != true && capacity == nil:
                    "If you are not using Limited as the event type, you should not fill in the arguements only for Limited events."
                timeLimited != true || timePeriod != nil: 
                    "If you create a FLOAT that can only be claimed in limited time, you must provide a timePeriod."
                capacityLimited != true || capacity != nil:
                    "If you create a Limited Capacity FLOAT, you must provide a capacity."
            }

            if type == ClaimOptions.Unlimited {
                self.events[name] = Unlimited(_host: self.owner!.address, _name: name, _description: description, _image: image)
            } else if type == ClaimOptions.Limited {
                timeLimited != true? false : true
                secretCodeLimited != true? false : true
                capacityLimited != true? false : true
                self.events[name] = Limited(_host: self.owner!.address, _name: name, _description: description, _image: image, _timeLimited: timeLimited!, _timePeriod: timePeriod, _secretCodeLimited: secretCodeLimited!, _capacityLimited: capacityLimited!, _capacity: capacity)
            } else if type == ClaimOptions.Admin {
                self.events[name] = Admin(_host: self.owner!.address, _name: name, _description: description, _image: image)
            }
        }

        // Toggles the event true/false and returns
        // the new state of it.
        // 
        // If an event is not active, you can never claim from it.
        pub fun toggleEventActive(name: String): Bool {
            pre {
                self.events[name] != nil: "This event does not exist in your Collection."
            }
            let eventRef = &self.events[name] as &{FLOATEvent}
            eventRef.info.active = !eventRef.info.active
            return eventRef.info.active
        }

        // Delete an event if you made a mistake.
        pub fun deleteEvent(name: String) {
            self.events.remove(key: name)
        }

        // A method for receiving a &FLOATEvent Capability. This is if 
        // a different account wants you to be able to handle their FLOAT Events
        // for them, so imagine if you're on a team of people and you all handle
        // one account.
        pub fun addCreationCapability(minter: Capability<&FLOATEvents>) {
            self.otherHosts[minter.borrow()!.owner!.address] = minter
        }

        // Get the Capability to do stuff with this FLOATEvents resource.
        pub fun getCreationCapability(host: Address): Capability<&FLOATEvents> {
            return self.otherHosts[host]!
        }

        // Get a {FLOATEvent} struct. The returned value is a copy.
        pub fun getEvent(name: String): {FLOATEvent} {
            return self.events[name] ?? panic("This event does not exist in this Collection.")
        }

        // If you have a `Secret` FLOATEvent and want to add the secretPhrase to it.
        // Once you do this, users will be able to claim their FLOAT if they had
        // previously typed in the same phrase you provided here.
        pub fun addSecretToEvent(name: String, secretPhrase: String) {
            pre {
                self.events[name] != nil : "This event does not exist in your Collection."
               }
            let ref = &self.events[name] as auth &{FLOATEvent}
            let secret = ref as! &Limited
            assert(secret.secretCodeLimited != true, message: "This event is not Limited by secret phrase")
            secret.secretPhrase = secretPhrase
        }

        // Return all the FLOATEvents you have ever created.
        pub fun getAllEvents(): {String: {FLOATEvent}} {
            return self.events
        }

        /*************************************** CLAIMING ***************************************/

        // Helper function for the 2 functions below.
        access(self) fun getEventRef(name: String): auth &{FLOATEvent} {
            return &self.events[name] as auth &{FLOATEvent}
        }

        // This is for claiming `Admin` FLOAT Events.
        //
        // For giving out FLOATs when the FLOAT Event is `Admin` type.
        pub fun distributeDirectly(name: String, recipient: &Collection{NonFungibleToken.CollectionPublic}) {
            pre {
                self.events[name] != nil:
                    "This event does not exist."
                self.events[name]!.type == ClaimOptions.Admin:
                    "This event is not an Admin type."
            }
            let FLOATEvent = self.getEventRef(name: name)
            FLOAT.mint(recipient: recipient, FLOATEvent: FLOATEvent)
        }

        // This is for claiming `Open`, `Timelock`, `Secret`, or `Limited` FLOAT Events.
        //
        // The `secret` parameter is only necessary if you're claiming a `Secret` FLOAT.
        pub fun claim(name: String, recipient: &Collection, secret: String?) {
            pre {
                self.getEvent(name: name).info.active: 
                    "This FLOATEvent is not active."
            }
            let FLOATEvent: auth &{FLOATEvent} = self.getEventRef(name: name)
            
            // For `Unlimited` FLOATEvents
            if FLOATEvent.type == ClaimOptions.Unlimited {
                FLOAT.mint(recipient: recipient, FLOATEvent: FLOATEvent)
                return
            }
            
            // For `Limited` FLOATEvents
            if FLOATEvent.type == ClaimOptions.Unlimited {
                let Limited: &Limited = FLOATEvent as! &Limited
                var qualify: Bool = false

                if Limited.secretCodeLimited {
                    if secret == nil {
                        panic("You must provide a secret phrase code to claim your FLOAT ahead of time.")
                    }

                    if Limited.secretPhrase == "" {
                        Limited.secretCodeAccounts[recipient.owner!.address] = secret
                        return
                    } else if Limited.secretCodeAccounts[recipient.owner!.address] != Limited.secretPhrase {
                        return
                    } else {
                        qualify = true
                    }
                }

                if Limited.timeLimited {
                    if Limited.dateEnding! <= getCurrentBlock().timestamp {
                        panic("Sorry! The time has run out to mint this Timelock FLOAT.")
                    } else {
                        qualify = true
                    }
                }

                if Limited.capacityLimited {
                    let currentCapacity = UInt64(Limited.capacityAccounts.length)
                    if currentCapacity < Limited.capacity! {
                        Limited.capacityAccounts[currentCapacity + 1] = recipient.owner!.address
                        qualify = true
                    }
                }

                if qualify {
                    FLOAT.mint(recipient: recipient, FLOATEvent: FLOATEvent)
                }
                return
            }
        }

        /******************************************************************************/

        init() {
            self.events = {}
            self.otherHosts = {}
        }
    }

    pub fun createEmptyCollection(): @Collection {
        return <- create Collection()
    }

    pub fun createEmptyFLOATEventCollection(): @FLOATEvents {
        return <- create FLOATEvents()
    }

    // Helper function to mint FLOATs.
    access(account) fun mint(recipient: &Collection{NonFungibleToken.CollectionPublic}, FLOATEvent: &{FLOATEvent}) {
        pre {
            FLOATEvent.info.claimed[recipient.owner!.address] == nil:
                "This person already claimed their FLOAT!"
        }
        let serial: UInt64 = FLOATEvent.info.totalSupply
        let token <- create NFT(_recipient: recipient.owner!.address, _info: FLOATEvent.info, _serial: serial) 
        recipient.deposit(token: <- token)
        FLOATEvent.info.claimed[recipient.owner!.address] = serial
        FLOATEvent.info.totalSupply = serial + 1
    }

    init() {
        self.totalSupply = 0
        emit ContractInitialized()

        self.FLOATCollectionStoragePath = /storage/FLOATCollectionStoragePath
        self.FLOATCollectionPublicPath = /public/FLOATCollectionPublicPath
        self.FLOATEventsStoragePath = /storage/FLOATEventsStoragePath
        self.FLOATEventsPublicPath = /public/FLOATEventsPublicPath
        self.FLOATEventsPrivatePath = /private/FLOATEventsPrivatePath
    }
}